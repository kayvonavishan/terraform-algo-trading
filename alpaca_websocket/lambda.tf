# Specify the AWS provider and region
#provider "aws" {
#  region = var.aws_region
#}

###############################
# IAM Role and Policy for Lambda
###############################

# Define the trust policy for Lambda to assume the role
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Create an IAM role for the Lambda function
resource "aws_iam_role" "lambda_role" {
  name               = "git_clone_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "git_clone_lambda_policy"
  description = "Allow Lambda function to access Secrets Manager, CloudWatch Logs, describe EC2 instances, interact with SSM, and manage network interfaces."
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Sid": "EC2DescribeInstances",
      "Effect": "Allow",
      "Action": "ec2:DescribeInstances",
      "Resource": "*"
    },
    {
      "Sid": "SSMAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2NetworkInterfaceManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}




# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

###############################
# Lambda Function
###############################

# Define the Lambda function resource
resource "aws_lambda_function" "git_clone_lambda" {
  function_name = "GitCloneLambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "alpaca_websocket.lambda_function.lambda_handler"
  runtime       = "python3.8"  # Change to your desired Python runtime version

  filename         = "deployment-package.zip"
  source_code_hash = filebase64sha256("deployment-package.zip")

  environment {
    variables = {
      GITHUB_SECRET_ID = "github/ssh-key"
      # Optionally override AWS_REGION if needed:
      # AWS_REGION = "us-east-1"
    }
  }

  # Adjust the timeout as needed (in seconds)
  timeout = 30

  # VPC configuration connecting Lambda to the same subnet and security group as the EC2 instance
  vpc_config {
    subnet_ids         = ["subnet-00aa2b4ebf4b670ef"]
    security_group_ids = ["sg-06612080dc355b148"]
  }
}


###############################
# (Optional) Outputs
###############################

output "lambda_function_name" {
  value = aws_lambda_function.git_clone_lambda.function_name
}
