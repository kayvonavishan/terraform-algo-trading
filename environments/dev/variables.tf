# Development Environment Variables

variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "bucket_name" {
  description = "The S3 bucket name containing your model structure"
  type        = string
  default     = "algo-model-deploy-dev"
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
    websocket_server = "t2.micro"
    trading_server   = "t2.micro"
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