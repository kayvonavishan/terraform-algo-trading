#!/bin/bash
# Ensure we are in the writable /tmp directory
cd /tmp

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
  sudo -u ec2-user git fetch > /home/ec2-user/ingestion.log
  sudo -u ec2-user git checkout feature/deployment-final-v2 >> /home/ec2-user/ingestion.log
  sudo -u ec2-user git pull >> /home/ec2-user/ingestion.log
else
  echo "Repository exists. Pulling latest changes..."
  git config --global --add safe.directory /home/ec2-user/algo-modeling-v2
  rm -R algo-modeling-v2
  sudo -u ec2-user git clone https://kayvonavishan:$MYSSHKEY@github.com/kayvonavishan/algo-modeling-v2.git
  sudo chown -R ec2-user:ec2-user /home/ec2-user/algo-modeling-v2
  cd algo-modeling-v2
  sudo -u ec2-user git fetch >> /home/ec2-user/ingestion.log
  sudo -u ec2-user git checkout feature/deployment-final-v2 >> /home/ec2-user/ingestion.log
  sudo -u ec2-user git pull >> /home/ec2-user/ingestion.log
fi

# Start the NATS server in the background.
echo "Starting nats-server..."
nohup nats-server -DV -m 8222 > /home/ec2-user/nats.log 2>&1 &

# Run the Python ingestion script.
echo "Running alpaca_ingestion.py..."
sudo -u ec2-user /usr/bin/python3 backup_vscode/deployment/alpaca_ingestion.py >> /home/ec2-user/ingestion.log 2>&1 &
