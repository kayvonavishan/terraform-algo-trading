#!/bin/bash
# Script: deploy_and_run.sh
# Description:
#   1. Retrieves the EC2 instance public IP by filtering with its Name tag.
#   2. SSHes into the instance and:
#      a. Fetches the private SSH key from AWS Secrets Manager.
#      b. Configures SSH to use this key for Git operations.
#      c. Checks if the repository exists; if not, clones it, or else pulls updates.
#      d. Starts the nats-server in the background.
#      e. Runs the python script 'alpaca_ingestion.py'.
#
# Prerequisites:
#   - AWS CLI is installed and configured.
#   - The EC2 instance has an IAM role with permission to access Secrets Manager.
#   - You have the key to SSH into the instance (specified by KEY_PATH).

# ---------------------- Configuration Variables -------------------------
INSTANCE_TAG_NAME="alpaca-instance"
KEY_PATH="/path/to/algo-deployment.pem"  # Update with the path to your EC2 instance key pair
SSH_USER="ec2-user"                     # Adjust for your AMI
SECRET_NAME="github/ssh-key"            # The name of your secret in Secrets Manager
GIT_REPO="git@github.com:kayvonavishan/algo-modeling-v2.git"
# -------------------------------------------------------------------------

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

# Retrieve the private SSH key from AWS Secrets Manager
echo "Fetching GitHub SSH key from Secrets Manager..."
aws secretsmanager get-secret-value \
  --secret-id "github/ssh-key" \
  --query 'SecretString' \
  --output text > ~/.ssh/github_rsa

# Secure the key file.
chmod 600 ~/.ssh/github_rsa

# Optionally add GitHub to known hosts to avoid SSH authenticity prompts.
ssh-keyscan github.com >> ~/.ssh/known_hosts

# Configure Git to use the retrieved SSH key.
export GIT_SSH_COMMAND="ssh -i ~/.ssh/github_rsa"

# Change to the home directory.
cd ~

# Check if the private repository already exists. If not, clone it; otherwise, pull updates.
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

echo "Deployment script complete."
