variable "aws_region" {
  description = "The AWS region for deployment."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (qa, prod, etc.)"
  type        = string
}