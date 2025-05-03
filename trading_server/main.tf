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
  # regex matching "models/<type>/<symbol>/<anything>-outer_<digits>_inner_<digits>"
  inner_pattern = "^models/[^/]+/[^/]+/[^/]+-outer_[0-9]+_inner_[0-9]+"

  # extract the unique 4-segment prefixes that match your outer/inner pattern
  matching_prefixes = distinct([
    for key in data.aws_s3_objects.models.keys :
    regexall(local.inner_pattern, key)[0]
    if length(regexall(local.inner_pattern, key)) > 0
  ])

  # split each prefix into its four parts
  split_keys = [
    for p in local.matching_prefixes :
    regexall("[^/]+", p)
  ]

  # map each folder to its attributes
  model_info_attrs = {
    for segs in local.split_keys :
    join("/", segs) => {
      model_type   = segs[1]   # e.g. "long"
      symbol       = segs[2]   # e.g. "SOXL"
      model_number = segs[3]   # e.g. "soxl_long-outer_11_inner_48"
    }
  }
}

output "matching_prefixes" {
  description = "Unique S3 prefixes matching the outer/inner pattern"
  value       = local.matching_prefixes
}


output "split_keys" {
  description = "Map of model information extracted from file prefixes."
  value       = local.split_keys
}


output "model_info_attrs" {
  description = "Map of model information extracted from file prefixes."
  value       = local.model_info_attrs
}


###############################
# IAM Role and Policies for EC2
###############################
# S3 Bucket Policy: allow our EC2 role to ListBucket & GetObject
resource "aws_s3_bucket_policy" "allow_instance_s3_access" {
  bucket = var.bucket_name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListBucket",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/trading_server_instance_role"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${var.bucket_name}"
    },
    {
      "Sid": "AllowGetObject",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/trading_server_instance_role"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${var.bucket_name}/*"
    },
    {
      "Sid": "AllowPutObject",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/trading_server_instance_role"
      },
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::${var.bucket_name}/*"
    }
  ]
}
EOF
}


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

# Inline IAM policy for S3 ListBucket access
resource "aws_iam_role_policy" "s3_list_policy" {
  name = "s3-list-access"
  role = aws_iam_role.instance_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "s3:ListBucket",
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::algo-model-deploy"
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
    echo "bucket_name=${var.bucket_name}" > $${CONFIG_FILE}
    echo "model_type=${each.value.model_type}" >> $${CONFIG_FILE}
    echo "symbol=${each.value.symbol}" >> $${CONFIG_FILE}
    echo "model_number=${each.value.model_number}" >> $${CONFIG_FILE}

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
