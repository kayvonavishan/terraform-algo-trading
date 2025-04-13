#!/bin/bash
# Ensure we are in the writable /tmp directory
cd /tmp

# (Optional) Print a message to indicate local execution by SSM
echo "Executing commands on the EC2 instance locally via SSM..."

# Ensure the .ssh directory exists with the proper permissions.
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Retrieve the GitHub SSH key from Secrets Manager using the AWS CLI.
echo "Fetching GitHub SSH key from Secrets Manager..."
aws secretsmanager get-secret-value \
  --secret-id "github/ssh-key" \
  --query 'SecretString' \
  --output text > ~/.ssh/github_rsa

chmod 600 ~/.ssh/github_rsa

# Add GitHub to known hosts.
ssh-keyscan github.com >> ~/.ssh/known_hosts

# Set the Git SSH command to use the retrieved GitHub key.
export GIT_SSH_COMMAND="ssh -i ~/.ssh/github_rsa"

# Change to the home directory.
cd ~

# Check if the repository already exists; if not, clone it; if it does, pull updates.
if [ ! -d "algo-modeling-v2" ]; then
  echo "Repository not found. Cloning the repository..."
  git clone "git@github.com:kayvonavishan/algo-modeling-v2.git"
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
