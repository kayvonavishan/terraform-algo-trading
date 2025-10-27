# AWS provider configuration is expected to be provided by the calling environment

# Data source to find the most recent AMI with the specified name pattern
data "aws_ami" "alpaca" {
  most_recent = true
  
  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }
  
  owners = ["self"]
}

# Data source to get the current AWS account id (used in IAM policy resources)
data "aws_caller_identity" "current" {}

###############################
# IAM Role and Policies for EC2
###############################

# Create an IAM role for the EC2 instance. This allows the instance to interact with AWS services.
resource "aws_iam_role" "instance_role" {
  name = "alpaca_instance_role_${var.environment}"
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
  name = "secretsmanager-access-${var.environment}"
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

resource "aws_iam_role_policy" "s3_config_read" {
  name = "s3-config-read-${var.environment}"
  role = aws_iam_role.instance_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGetConfigObject",
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::${var.bucket_name}/configs/*"
    },
    {
      "Sid": "AllowListConfigPrefix",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::${var.bucket_name}",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["configs/*"]
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dashboard_policy" {
  name = "dashboard-access-${var.environment}"
  role = aws_iam_role.instance_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DescribeTradingInstances",
      "Effect": "Allow",
      "Action": ["ec2:DescribeInstances"],
      "Resource": "*"
    },
    {
      "Sid": "SendHealthCheckCommand",
      "Effect": "Allow",
      "Action": ["ssm:SendCommand"],
      "Resource": [
        "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
        "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"
      ]
    },
    {
      "Sid": "ReadCommandStatus",
      "Effect": "Allow",
      "Action": [
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations"
      ],
      "Resource": "*"
    },
    {
      "Sid": "GetTradeObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::${var.bucket_name}/models/*/*/*/trades/*"
    },
    {
      "Sid": "AllowListAllModelsPrefix",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::${var.bucket_name}"
    },
    {
      "Sid": "GetTradeObjectsAndLogs",
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": [
        "arn:aws:s3:::${var.bucket_name}/models/*/*/*/trades/*",
        "arn:aws:s3:::${var.bucket_name}/models/*/*/*/logs/app.log" 
      ]
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
  name = "alpaca_instance_profile_${var.environment}"
  role = aws_iam_role.instance_role.name
}

###############################
# EC2 Instance Resource
###############################

# Resource to create the EC2 instance with the IAM instance profile attached.
resource "aws_instance" "alpaca_instance" {
  ami                   = data.aws_ami.alpaca.id
  instance_type         = var.instance_type

  # Specify the subnet (this subnet belongs to your VPC, adjust as needed)
  subnet_id             = "subnet-00aa2b4ebf4b670ef"

  # Specify the key pair to use for SSH access.
  key_name              = var.key_name

  # Reference the security group ID (ensure this security group is correct for your VPC)
  vpc_security_group_ids = [
    "sg-06612080dc355b148",
  ]

  # Configure root volume to delete on termination
  root_block_device {
    delete_on_termination = true
    volume_type           = "gp3"
    volume_size           = 14
  }

  # User data script that outputs configuration details to a file in /home/ec2-user/deployment_config.txt
  user_data = <<-EOF
    #!/bin/bash
    pip install boto3 ##This should be apart of the AMI!
    pip install streamlit
    CONFIG_FILE="/home/ec2-user/deployment_config.txt"

    # Write or overwrite the configuration file with the deployment information.
    echo "bucket_name=${var.bucket_name}" > $${CONFIG_FILE}
    echo "git_branch=${var.git_branch}" >> $${CONFIG_FILE}

    # Optional: Print to the console for debugging/logging purposes.
    echo "Deployment config written to $${CONFIG_FILE}"
  EOF
  
  # Attach the IAM instance profile so that the instance can access Secrets Manager and SSM.
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  # Optional: Tag your instance for easier identification.
  tags = {
    Name = "alpaca-websocket-ingest-${var.environment}"
    Environment = var.environment
  }
}
