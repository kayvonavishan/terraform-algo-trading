# QA Environment Variables

variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "qa"
}

variable "bucket_name" {
  description = "The S3 bucket name containing your model structure"
  type        = string
  default     = "algo-model-deploy"
}

variable "key_name" {
  description = "The key pair name to use for the EC2 instances"
  type        = string
  default     = "algo-deployment"
}

variable "instance_types" {
  description = "EC2 instance types for different services"
  type = object({
    websocket_server = string
    trading_server   = string
  })
  default = {
    websocket_server = "t2.small"
    trading_server   = "t2.small"
  }
}

variable "ami_name_filters" {
  description = "AMI name filter patterns for different services"
  type = object({
    websocket_server = string
    trading_server   = string
  })
  default = {
    websocket_server = "alpaca-websocket*"
    trading_server   = "trading-server*"
  }
}

variable "git_branch" {
  description = "Git branch to checkout for algo-modeling-v2 repository"
  type        = string
  default     = "feature/wire-streaming-val"
}