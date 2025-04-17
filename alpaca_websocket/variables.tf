# Define variables
variable "aws_region" {
  description = "AWS region to deploy in"
  default     = "us-east-1"  # Change as needed.
}

variable "bucket_name" {
  description = "The S3 bucket name containing your model structure."
  default     = "algo-model-deploy"
}