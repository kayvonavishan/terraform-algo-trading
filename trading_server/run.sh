#!/bin/bash

sudo yum install -y cronie ##Should be apart of AMI!
sudo systemctl start crond

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
  sudo -u ec2-user git fetch > /home/ec2-user/live_trader.log
  sudo -u ec2-user git checkout feature/deployment-final-v2 >> /home/ec2-user/live_trader.log
  sudo -u ec2-user git pull >> /home/ec2-user/live_trader.log
else
  echo "Repository exists. Pulling latest changes..."
  git config --global --add safe.directory /home/ec2-user/algo-modeling-v2
  rm -R algo-modeling-v2
  sudo -u ec2-user git clone https://kayvonavishan:$MYSSHKEY@github.com/kayvonavishan/algo-modeling-v2.git
  sudo chown -R ec2-user:ec2-user /home/ec2-user/algo-modeling-v2
  cd algo-modeling-v2
  sudo -u ec2-user git fetch >> /home/ec2-user/live_trader.log
  sudo -u ec2-user git checkout feature/deployment-final-v2 >> /home/ec2-user/live_trader.log
  sudo -u ec2-user git pull >> /home/ec2-user/live_trader.log
fi

#grab the passed‑in NATS IP (this is passed in lambda_function.py)
CONFIG="/home/ec2-user/deployment_config.txt"
#update or append the line
if grep -q '^nats_public_ip=' "$CONFIG"; then
  sed -i "s|^nats_public_ip=.*|nats_public_ip=$NATS_PUBLIC_IP|" "$CONFIG"
else
  echo "nats_public_ip=$NATS_PUBLIC_IP" >> "$CONFIG"
fi

# -------------------------------------------------------
# 1) Create the standalone upload script
# -------------------------------------------------------
cat <<'EOF' > /usr/local/bin/upload_app_log.sh
#!/bin/bash
# loads S3 target from deployment_config.txt and pushes live_trader.log → app.log
# load variables
source /home/ec2-user/deployment_config.txt

set -euo pipefail
S3_ROOT="s3://${bucket_name}/models/${model_type}/${symbol}/${model_number}"


# perform upload (always overwrites app.log)
aws s3 cp \
  /home/ec2-user/live_trader.log \
  s3://"$bucket_name"/models/"$model_type"/"$symbol"/"$model_number"/logs/app.log

# 2) Upload today’s (and any back‑filled) trade files – skips unchanged files
aws s3 sync /home/ec2-user/ "${S3_ROOT}/trades/" \
  --exclude "*" \
  --include "/home/ec2-user/trades_*.csv" \
  --only-show-errors
EOF

chmod +x /usr/local/bin/upload_app_log.sh
echo "Created /usr/local/bin/upload_app_log.sh"

# -------------------------------------------------------
# 2) Ensure the cron job is in ec2-user's crontab
# -------------------------------------------------------
CRON_CMD="*/15 * * * * sleep 45 && /usr/local/bin/upload_app_log.sh"
# only add if not already present
if ! crontab -u ec2-user -l 2>/dev/null | grep -Fq "/usr/local/bin/upload_app_log.sh"; then
  ( crontab -u ec2-user -l 2>/dev/null; echo "$CRON_CMD" ) | crontab -u ec2-user -
  echo "Installed cron entry for ec2-user: $CRON_CMD"
else
  echo "Cron entry already exists for upload_app_log.sh"
fi

#delete old log file
if [ -f /home/ec2-user/live_trader.log ]; then
  rm /home/ec2-user/live_trader.log
  echo "Deleted /home/ec2-user/live_trader.log"
else
  echo "File does not exist, nothing to do."
fi


# Run the Python ingestion script.
echo "Running live_trader.py..."
cd backup_vscode
sudo -u ec2-user /usr/local/bin/python3.12 deployment/live_trader.py >> /home/ec2-user/live_trader.log 2>&1 &
