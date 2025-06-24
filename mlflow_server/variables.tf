variable "aws_region" { type = string; default = "us-east-1" }

variable "vpc_id" {
  description = "VPC to deploy into (defaults to default VPC)"
  type        = string
  default     = null
}

variable "public_subnet_id" {
  description = "Public subnet for the EC2 instance (defaults to first public subnet)"
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "Private subnets for the Aurora cluster (defaults to two private subnets)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDRs that may reach SSH + MLflow UI"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mlflow_version" { type = string; default = "2.12.2" }

variable "instance_type" { type = string; default = "t3.micro" }
variable "mlflow_port" { type = number; default = 5000 }