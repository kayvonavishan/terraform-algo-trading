# Define variables
variable "aws_region" {
  description = "AWS region to deploy in"
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
  description = "EC2 instance type for websocket server"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "The key pair name to use for the EC2 instances."
  type        = string
  default     = "algo-deployment"
}

variable "ami_name_filter" {
  description = "AMI name filter pattern"
  type        = string
  default     = "alpaca-websocket*"
}

variable "enable_eventbridge" {
  description = "Enable EventBridge scheduling for Lambda function"
  type        = bool
  default     = true
}