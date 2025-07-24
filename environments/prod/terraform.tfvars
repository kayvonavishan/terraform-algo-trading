# Production Environment Configuration Values

environment = "prod"
bucket_name = "algo-model-deploy-prod"
aws_region  = "us-east-1"
key_name    = "algo-deployment"

# Instance types optimized for production workloads
instance_types = {
  websocket_server = "t2.small"
  trading_server   = "t2.small"
}

# AMI name filters - use tested and validated AMI versions from QA
ami_name_filters = {
  websocket_server = "alpaca-websocket*"
  trading_server   = "trading-server*"
}

# Git branch for production - use live branch for production code
git_branch = "live"