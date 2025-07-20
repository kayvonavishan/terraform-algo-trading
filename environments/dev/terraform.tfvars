# Development Environment Configuration Values

environment = "dev"
bucket_name = "algo-model-deploy-dev"
aws_region  = "us-east-1"
key_name    = "algo-deployment"

# Instance types optimized for development (smallest/cheapest)
instance_types = {
  websocket_server = "t2.micro"
  trading_server   = "t2.micro"
}

# AMI name filters - use development or latest versions
ami_name_filters = {
  websocket_server = "alpaca-websocket*"
  trading_server   = "trading-server*"
}

# Git branch for development - use main branch for latest stable code
git_branch = "main"