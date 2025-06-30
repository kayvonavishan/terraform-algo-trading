variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_id" {
  description = "Optional: existing VPC ID. Defaults to AWS default VPC."
  type        = string
  default     = null
}

variable "public_subnet_id" {
  description = "Optional: specific public subnet for the EC2 instance."
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "Optional: list of private subnet IDs for Aurora."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDRs allowed to reach SSH and MLflow UI."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mlflow_version" {
  type    = string
  default = "3.1.1"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "mlflow_port" {
  type    = number
  default = 5000
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for two new private subnets (in different AZs)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "ssh_key_name" {
  description = "Existing AWS key pair for SSH"
  type        = string
  default     = "algo-deployment"
}