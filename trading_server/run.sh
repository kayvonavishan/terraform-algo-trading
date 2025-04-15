#!/bin/bash

# (Optional) Print a message to indicate local execution by SSM
echo "Executing commands on the EC2 instance locally via SSM..."


# Retrieve the GitHub SSH key from Secrets Manager using the AWS CLI.
echo "Fetching GitHub SSH key from Secrets Manager..."
aws secretsmanager get-secret-value \
  --secret-id "github/ssh-key" \
  --query 'SecretString' \
  --output text > ~/github_token

export MYSSHKEY=$(jq -r '.["private-key"]' ~/github_token)

git config set --global remote.origin.url "https://kayvonavishan:${MYSSHKEY}@github.com/kayvonavishan/algo-modeling-v2.git"


# Change to the home directory.
cd /home/ec2-user

# Check if the repository already exists; if not, clone it; if it does, pull updates.
if [ ! -d "algo-modeling-v2" ]; then
  echo "Repository not found. Cloning the repository..."
  git clone https://kayvonavishan:$MYSSHKEY@github.com/kayvonavishan/algo-modeling-v2.git
  git checkout feature/deployment
  cd algo-modeling-v2
else
  echo "Repository exists. Pulling latest changes..."
  cd algo-modeling-v2
  git checkout feature/deployment
  git pull
fi

# Run the Python ingestion script.
echo "Running live_trader.py..."
sudo -u ec2-user /usr/bin/python3 backup_vscode/deployment/live_trader.py > /home/ec2-user/live_trader.log 2>&1 &
