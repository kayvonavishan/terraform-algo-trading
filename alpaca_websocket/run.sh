#!/bin/bash
# Script: deploy_and_run.sh
# Description:
#   1. Retrieves the EC2 instance public IP by filtering with its Name tag.
#   2. Retrieves the algo-deployment.pem file (used for SSH into the EC2 instance) from AWS Secrets Manager.
#      The secret is named "algo-deployment.pem" and the key containing the PEM is "key".
#   3. SSHes into the instance and:
#      a. Fetches the GitHub SSH key from AWS Secrets Manager.
#      b. Configures SSH to use this key for Git operations.
#      c. Checks if the repository exists; if not, clones it; otherwise, pulls updates.
#      d. Starts the nats-server in the background.
#      e. Runs the Python script 'alpaca_ingestion.py'.
#
# Prerequisites:
#   - AWS CLI is installed and configured.
#   - Python is installed and available in your PATH.
#   - The EC2 instance has an IAM role with permission to access Secrets Manager.
#   - The secrets for the algo-deployment key and the GitHub SSH key are stored in Secrets Manager.

# ---------------------- Configuration Variables -------------------------
INSTANCE_TAG_NAME="alpaca-websocket-ingest"
ALGO_KEY_SECRET="algo-deployment.pem"    # Secret name in Secrets Manager
SSH_USER="ec2-user"                       # Adjust for your AMI
GITHUB_SECRET_NAME="github/ssh-key"       # The secret name for the GitHub SSH key in Secrets Manager
GIT_REPO="git@github.com:kayvonavishan/algo-modeling-v2.git"
# -------------------------------------------------------------------------

# Retrieve the algo-deployment.pem file from Secrets Manager.
# The secret is expected to be a JSON object with a "key" property containing the PEM.
echo "Fetching algo-deployment.pem from Secrets Manager..."
aws secretsmanager get-secret-value \
  --secret-id "$ALGO_KEY_SECRET" \
  --query 'SecretString' \
  --output text | python -c "import json,sys; print(json.load(sys.stdin)['key'])" > algo-deployment.pem

if [ $? -ne 0 ]; then
  echo "Error: Could not retrieve algo-deployment.pem from Secrets Manager."
  exit 1
fi

# Secure the key file.
chmod 600 algo-deployment.pem
KEY_PATH="./algo-deployment.pem"

echo "Fetching the EC2 instance public IP..."
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${INSTANCE_TAG_NAME}" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text)

if [ -z "$INSTANCE_IP" ] || [ "$INSTANCE_IP" == "None" ]; then
  echo "Error: Could not find a running instance with tag Name=${INSTANCE_TAG_NAME}."
  exit 1
fi

echo "Connecting to EC2 instance at ${INSTANCE_IP}..."

# SSH into the instance and run the remote commands.
ssh -i "$KEY_PATH" "$SSH_USER@$INSTANCE_IP" << 'EOF'
# Ensure the .ssh directory exists and has correct permissions.
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Retrieve the GitHub SSH key from AWS Secrets Manager.
echo "Fetching GitHub SSH key from Secrets Manager..."
aws secretsmanager get-secret-value \
  --secret-id "github/ssh-key" \
  --query 'SecretString' \
  --output text > ~/.ssh/github_rsa

# Secure the GitHub key file.
chmod 600 ~/.ssh/github_rsa

# Optionally add GitHub to known hosts to avoid SSH authenticity prompts.
ssh-keyscan github.com >> ~/.ssh/known_hosts

# Configure Git to use the retrieved SSH key.
export GIT_SSH_COMMAND="ssh -i ~/.ssh/github_rsa"

# Change to the home directory.
cd ~

# Check if the repository already exists. If not, clone it; otherwise, pull updates.
if [ ! -d "algo-modeling-v2" ]; then
  echo "Repository not found. Cloning the repository..."
  git clone "${GIT_REPO}"
  cd algo-modeling-v2
else
  echo "Repository exists. Pulling latest changes..."
  cd algo-modeling-v2
  git pull
fi

# Start the NATS server in the background.
echo "Starting nats-server..."
nohup nats-server -DV -m 8222 > nats.log 2>&1 &

# Run the Python ingestion script.
echo "Running alpaca_ingestion.py..."
python alpaca_ingestion.py

EOF

# Remove the PEM file after it's no longer needed.
rm -f algo-deployment.pem
echo "Local algo-deployment.pem removed."

echo "Deployment script complete."
