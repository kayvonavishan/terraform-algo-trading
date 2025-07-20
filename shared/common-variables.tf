# Common variables used across multiple environments

variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (qa, prod, etc.)"
  type        = string
  validation {
    condition     = contains(["qa", "prod", "dev"], var.environment)
    error_message = "Environment must be one of: qa, prod, dev."
  }
}

variable "bucket_name" {
  description = "The S3 bucket name containing your model structure"
  type        = string
}

variable "key_name" {
  description = "The key pair name to use for the EC2 instances"
  type        = string
  default     = "algo-deployment"
}

# Instance type configurations for different environments
variable "instance_types" {
  description = "EC2 instance types for different services"
  type = object({
    websocket_server = string
    trading_server   = string
  })
  default = {
    websocket_server = "t3.small"
    trading_server   = "t2.small"
  }
}

# AMI name filters for different environments
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

# Network configuration (these would need to be updated with your actual values)
variable "vpc_config" {
  description = "VPC configuration"
  type = object({
    subnet_id         = string
    security_group_ids = list(string)
  })
  default = {
    subnet_id         = "subnet-00aa2b4ebf4b670ef"
    security_group_ids = ["sg-06612080dc355b148"]
  }
}