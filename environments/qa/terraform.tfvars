# QA Environment Configuration Values

environment = "qa"
bucket_name = "algo-model-deploy"
aws_region  = "us-east-1"
key_name    = "algo-deployment"

# Instance types optimized for QA workloads
instance_types = {
  websocket_server = "t2.small"
  trading_server   = "t2.small"
}

# AMI name filters - use specific versions for QA testing
ami_name_filters = {
  websocket_server = "alpaca-websocket*"
  trading_server   = "trading-server*"
}

# Git branch for QA testing - use main branch for stable testing
git_branch = "main"