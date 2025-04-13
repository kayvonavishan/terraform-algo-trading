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

# Create an IAM policy that allows access to Secrets Manager and CloudWatch Logs
resource "aws_iam_policy" "lambda_policy" {
  name        = "git_clone_lambda_policy"
  description = "Allow Lambda function to access Secrets Manager and CloudWatch Logs"
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

  # Path to your deployment package ZIP file
  filename         = "deployment-package.zip"
  source_code_hash = filebase64sha256("alpaca_websocket/deployment-package.zip")

  # Environment variables for the Lambda function.
  # Ensure that 'GITHUB_SECRET_ID' matches the name of your secret in Secrets Manager.
  environment {
    variables = {
      GITHUB_SECRET_ID = "github/ssh-key"
      # Optionally override AWS_REGION if needed:
      # AWS_REGION = "us-east-1"
    }
  }

  # Adjust the timeout as needed (in seconds)
  timeout = 30
}

###############################
# (Optional) Outputs
###############################

output "lambda_function_name" {
  value = aws_lambda_function.git_clone_lambda.function_name
}
