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
export HOME=/home/ec2-user


# Check if the repository already exists; if not, clone it; if it does, pull updates.
if [ ! -d "algo-modeling-v2" ]; then
  echo "Repository not found. Cloning the repository..."
  sudo -u ec2-user git clone https://kayvonavishan:$MYSSHKEY@github.com/kayvonavishan/algo-modeling-v2.git
  sudo chown -R ec2-user:ec2-user /home/ec2-user/algo-modeling-v2
  cd algo-modeling-v2
  sudo -u ec2-user git fetch >> /home/ec2-user/live_trader.log
  sudo -u ec2-user git checkout feature/deployment >> /home/ec2-user/live_trader.log
  sudo -u ec2-user git pull >> /home/ec2-user/live_trader.log
else
  echo "Repository exists. Pulling latest changes..."
  git config --global --add safe.directory /home/ec2-user/algo-modeling-v2
  rm -R algo-modeling-v2
  sudo -u ec2-user git clone https://kayvonavishan:$MYSSHKEY@github.com/kayvonavishan/algo-modeling-v2.git
  sudo chown -R ec2-user:ec2-user /home/ec2-user/algo-modeling-v2
  cd algo-modeling-v2
  sudo -u ec2-user git fetch >> /home/ec2-user/live_trader.log
  sudo -u ec2-user git checkout feature/deployment >> /home/ec2-user/live_trader.log
  sudo -u ec2-user git pull >> /home/ec2-user/live_trader.log
fi

# Run the Python ingestion script.
echo "Running live_trader.py..."
cd backup_vscode
sudo -u ec2-user /usr/bin/python3 deployment/live_trader.py >> /home/ec2-user/live_trader.log 2>&1 &
