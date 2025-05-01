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
  name               = "trading_server_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "trading_server_lambda_policy"
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

##################################################
# ZIP up the contents of trading_server/ on every plan
##################################################

locals {
  # 1) grab every file under the module
  all_files = fileset("${path.module}", "**")

  ## 2) grab only the files you _do_ want
  #wanted_files = concat(
  #  fileset("${path.module}", "trading_server/**/*.py"),
  #  ["requirements.txt"]
  #)
  #
  ## 3) everything not in wanted_files should be excluded
  #excludes = [
  #  for f in local.all_files : f
  #  if !(f in local.wanted_files)
  #]
}

output "all_files" {
  value = local.all_files
}



data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "."     # ✔ zips the TF folder + all your code files
  output_path = "./deployment-package.zip"

  # toss out anything that isn't runtime code
  excludes = [
    "*.tf",            # your Terraform files
    ".terraform/*",    # Terraform’s state/cache dir
  ]
}

###############################
# Lambda Function
###############################

# Define the Lambda function resource
resource "aws_lambda_function" "trading_server_lambda" {
  function_name = "TradingServerLambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"  # Change to your desired Python runtime version

  #filename         = "deployment-package.zip"
  #source_code_hash = filebase64sha256("deployment-package.zip")

  # point at the auto-built ZIP
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  environment {
    variables = {
      GITHUB_SECRET_ID = "github/ssh-key"
      # Optionally override AWS_REGION if needed:
      # AWS_REGION = "us-east-1"
    }
  }

  # Adjust the timeout as needed (in seconds)
  timeout = 30
  publish = true

}


###############################
# (Optional) Outputs
###############################

output "lambda_function_name" {
  value = aws_lambda_function.trading_server_lambda.function_name
}
