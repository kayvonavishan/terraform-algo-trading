# Specify the AWS provider and region
provider "aws" {
  region = var.aws_region
}

# Define variables
variable "aws_region" {
  description = "AWS region to deploy in"
  default     = "us-east-1"  # Change as needed.
}

# Data source to find the most recent AMI with the name 'alpaca-websocket-ingest'
data "aws_ami" "alpaca" {
  most_recent = true
  
  filter {
    name   = "name"
    values = ["alpaca-websocket-ingest"]
  }
  
  # Adjust this to match the owner of the AMI. If this is a private AMI owned by your account use "self".
  owners = ["self"]
}

# Data source to get the current AWS account id (used in IAM policy resources)
data "aws_caller_identity" "current" {}

# Create an IAM role for the EC2 instance
resource "aws_iam_role" "instance_role" {
  name = "alpaca_instance_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Attach an inline policy to the IAM role allowing access to Secrets Manager
resource "aws_iam_role_policy" "secrets_policy" {
  name = "secretsmanager-access"
  role = aws_iam_role.instance_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "secretsmanager:GetSecretValue",
      "Effect": "Allow",
      "Resource": "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:github/ssh-key*"
    }
  ]
}
EOF
}

# Create an IAM instance profile to attach the role to the EC2 instance.
resource "aws_iam_instance_profile" "instance_profile" {
  name = "alpaca_instance_profile"
  role = aws_iam_role.instance_role.name
}

# Resource to create the EC2 instance with the IAM instance profile attached
resource "aws_instance" "alpaca_instance" {
  ami                   = data.aws_ami.alpaca.id
  instance_type         = "t2.small"

  # Specify the subnet (this subnet belongs to vpc-0664c3730bd2e574b)
  subnet_id             = "subnet-00aa2b4ebf4b670ef"

  # Specify the key pair to use for SSH access.
  key_name              = "algo-deployment"

  # Reference the security group ID (this security group is assumed to be in the same VPC)
  vpc_security_group_ids = [
    "sg-06612080dc355b148",
  ]
  
  # Attach the IAM instance profile so the instance can access Secrets Manager
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  # Optional: Tag your instance for easier identification
  tags = {
    Name = "alpaca-websocket-ingest"
  }
}
