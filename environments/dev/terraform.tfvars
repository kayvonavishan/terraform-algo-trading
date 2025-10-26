# Development Environment Configuration Values

environment = "dev"
bucket_name = "algo-model-deploy-dev"
aws_region  = "us-east-1"
key_name    = "algo-deployment"

# Instance types optimized for development (smallest/cheapest)
instance_types = {
  websocket_server = "t2.small"
  trading_server   = "t2.small"
}

# AMI name filters - use development or latest versions
ami_name_filters = {
  websocket_server = "alpaca-websocket*"
  trading_server   = "trading-server*"
}

# Git branch for development - use feature/dev branch for development work
git_branch = "feature/wire-streaming-val"