# Configure the AWS provider
provider "aws" {
  region = var.aws_region
}

# Data source to list all objects under the "models/" prefix in the bucket.
data "aws_s3_objects" "models" {
  bucket = var.bucket_name
  prefix = "models/"
}

output "s3_model_object_keys" {
  description = "List of S3 object keys under the models/ prefix"
  value       = data.aws_s3_objects.models.keys
}

# Data source to find the most recent AMI with the name 'trading-server'
data "aws_ami" "trading_server" {
  most_recent = true

  filter {
    name   = "name"
    values = ["trading-server"]
  }

  # Adjust this to match the owner of the AMI. If this is a private AMI owned by your account use "self".
  owners = ["self"]
}

# Data source to get the current AWS account id (used in IAM policy resources)
data "aws_caller_identity" "current" {}

locals {
  # First, let’s extract non-empty segments for each key using regexall.
  split_keys = [
    for key in data.aws_s3_objects.models.keys :
    regexall("[^/]+", key)
  ]

  # Now, filter for keys that represent a model prefix.
  # For a prefix like "models/long/SOXL/model1/", the regexall output will be:
  # ["models", "long", "SOXL", "model1"]
  filtered_keys = [
    for key in local.split_keys :
    key if length(key) == 4 #&& startswith(key[3], "model")
  ]

  # Transform the filtered segments into a map with the desired attributes.
  model_info_attrs = {
    for parts in local.filtered_keys :
    join("/", parts) => {
      model_type   = parts[1]   // e.g., "long" or "short"
      symbol       = parts[2]   // e.g., "SOXL"
      model_number = parts[3]   // e.g., "model1"
    }
  }
}

output "split_keys" {
  description = "Map of model information extracted from file prefixes."
  value       = local.split_keys
}


output "filtered_keys" {
  description = "Map of model information extracted from file prefixes."
  value       = local.filtered_keys
}

output "model_info_attrs" {
  description = "Map of model information extracted from file prefixes."
  value       = local.model_info_attrs
}


###############################
# IAM Role and Policies for EC2
###############################

# Create an IAM role for the EC2 instance. This allows the instance to interact with AWS services.
resource "aws_iam_role" "instance_role" {
  name = "trading_server_instance_role"
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

# Attach an inline policy to the IAM role allowing access to Secrets Manager.
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

# ***** 1B: SSM Support *****
# Attach the AmazonSSMManagedInstanceCore managed policy so that the EC2 instance can use AWS Systems Manager (SSM).
resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create an IAM instance profile to attach the role to the EC2 instance.
resource "aws_iam_instance_profile" "instance_profile" {
  name = "trading_server_instance_profile"
  role = aws_iam_role.instance_role.name
}



## Provision an EC2 instance for each model.
resource "aws_instance" "model_instance" {
  # Create an instance for each S3 key modeled in local.model_info.
  for_each = local.model_info_attrs

  ami           = data.aws_ami.trading_server.id
  instance_type = var.instance_type
  key_name      = var.key_name

  # Reference the security group ID (ensure this security group is correct for your VPC)
  vpc_security_group_ids = [
    "sg-06612080dc355b148",
  ]

  # User data script that outputs configuration details to a file in /home/ec2-user/deployment_config.txt
  user_data = <<-EOF
    #!/bin/bash
    CONFIG_FILE="/home/ec2-user/deployment_config.txt"

    # Write or overwrite the configuration file with the deployment information.
    echo "Bucket Name: ${var.bucket_name}" > $${CONFIG_FILE}
    echo "Model Type: ${each.value.model_type}" >> $${CONFIG_FILE}
    echo "Symbol: ${each.value.symbol}" >> $${CONFIG_FILE}
    echo "Model Number: ${each.value.model_number}" >> $${CONFIG_FILE}

    # Optional: Print to the console for debugging/logging purposes.
    echo "Deployment config written to $${CONFIG_FILE}"
  EOF

  # Attach the IAM instance profile so that the instance can access Secrets Manager and SSM.
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  # Tag the instance with the extracted values.
  tags = {
    Name      = "trading-server-${each.value.symbol}-${each.value.model_type}-${each.value.model_number}"
    ModelType = each.value.model_type
    Symbol    = each.value.symbol
    ModelNumber = each.value.model_number
  }
}
