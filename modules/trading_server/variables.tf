variable "aws_region" {
  description = "The AWS region for deployment."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "The S3 bucket name containing your model structure."
  type        = string
}

variable "environment" {
  description = "Environment name (qa, prod, etc.)"
  type        = string
}

variable "instance_type" {
  description = "The instance type to deploy (e.g., t2.micro)."
  type        = string
  default     = "t2.small"
}

variable "key_name" {
  description = "The key pair name to use for the EC2 instances."
  type        = string
  default     = "algo-deployment"
}

variable "ami_name_filter" {
  description = "AMI name filter pattern"
  type        = string
  default     = "trading-server*"
}

variable "websocket_instance_name" {
  description = "Name of the websocket instance to connect to"
  type        = string
  default     = "alpaca-websocket-ingest"
}

variable "enable_eventbridge" {
  description = "Enable EventBridge infrastructure for Lambda function chaining"
  type        = bool
  default     = true
}

variable "git_branch" {
  description = "Git branch to checkout for algo-modeling-v2 repository"
  type        = string
  default     = "feature/wire-streaming-val"
}


