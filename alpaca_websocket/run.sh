#!/bin/bash
# Ensure we are in the writable /tmp directory
cd /tmp

# The PEM file should have already been written to /tmp by the Lambda function.
if [ ! -f "/tmp/algo-deployment.pem" ]; then
  echo "Error: PEM file not found in /tmp."
  exit 1
fi

# Use the pre-fetched PEM file.
KEY_PATH="/tmp/algo-deployment.pem"
chmod 600 "$KEY_PATH"

# Retrieve the instance IP from the environment variable.
if [ -z "$INSTANCE_IP" ]; then
  echo "Error: INSTANCE_IP environment variable not set."
  exit 1
fi

echo "Connecting to EC2 instance at ${INSTANCE_IP}..."

# SSH configuration.
SSH_USER="ec2-user"
GITHUB_SECRET_NAME="github/ssh-key"       # GitHub secret for SSH key; fetched on remote.
GIT_REPO="git@github.com:kayvonavishan/algo-modeling-v2.git"

# SSH into the EC2 instance to perform subsequent steps.
ssh -i "$KEY_PATH" "$SSH_USER@${INSTANCE_IP}" << 'EOF'
# Ensure the .ssh directory exists with the proper permissions.
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Retrieve the GitHub SSH key from Secrets Manager on the remote EC2 instance.
echo "Fetching GitHub SSH key from Secrets Manager..."
aws secretsmanager get-secret-value \
  --secret-id "github/ssh-key" \
  --query 'SecretString' \
  --output text > ~/.ssh/github_rsa

chmod 600 ~/.ssh/github_rsa
ssh-keyscan github.com >> ~/.ssh/known_hosts
export GIT_SSH_COMMAND="ssh -i ~/.ssh/github_rsa"

# Change to the home directory.
cd ~

# Check if the repository already exists. If not, clone it; if it does, pull updates.
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
