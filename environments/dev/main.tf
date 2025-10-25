# Development Environment Configuration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Alpaca WebSocket Module (no EventBridge scheduling)
module "alpaca_websocket" {
  source = "../../modules/alpaca_websocket"
  
  aws_region        = var.aws_region
  environment       = var.environment
  bucket_name       = var.bucket_name
  instance_type     = var.instance_types.websocket_server
  key_name          = var.key_name
  ami_name_filter   = var.ami_name_filters.websocket_server
  enable_eventbridge = false  # Disable EventBridge for dev
  git_branch         = var.git_branch
}

# Trading Server Module (no EventBridge chaining)
module "trading_server" {
  source = "../../modules/trading_server"
  
  aws_region              = var.aws_region
  environment             = var.environment
  bucket_name             = var.bucket_name
  instance_type           = var.instance_types.trading_server
  key_name                = var.key_name
  ami_name_filter         = var.ami_name_filters.trading_server
  websocket_instance_name = module.alpaca_websocket.instance_name
  alpaca_lambda_function_name = module.alpaca_websocket.lambda_function_name
  alpaca_lambda_role_name     = module.alpaca_websocket.lambda_role_name
  enable_eventbridge      = false  # Disable EventBridge for dev
  git_branch              = var.git_branch
}

# Note: trading_server_shutdown module is intentionally omitted for dev environment

# Outputs
output "websocket_instance_id" {
  description = "ID of the websocket instance"
  value       = module.alpaca_websocket.instance_id
}

output "model_info" {
  description = "Information about deployed models"
  value       = module.trading_server.model_info_attrs
}

output "trading_server_instances" {
  description = "Trading server instance information"
  value       = module.trading_server.instance_info
}
