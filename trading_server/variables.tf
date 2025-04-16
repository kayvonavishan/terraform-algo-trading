variable "aws_region" {
  description = "The AWS region for deployment."
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "The S3 bucket name containing your model structure."
  default     = "algo-model-deploy"
}

variable "instance_type" {
  description = "The instance type to deploy (e.g., t2.micro)."
  default     = "t2.small"
}

variable "key_name" {
  description = "The key pair name to use for the EC2 instances."
  default     = "algo-deployment"
}


