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
  name               = "alpaca_websocket_lambda_role_${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "alpaca_websocket_lambda_policy_${var.environment}"
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
      "Sid": "EC2Instances",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",  
        "ec2:StartInstances",
        "ec2:StopInstances"            
      ],
      "Resource": "*"
    },
    {                        
      "Sid": "SSMAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations"   
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

# Allow the Alpaca role to call InvokeFunction on TradingServerLambda
# Using constructed ARN to avoid circular dependency
resource "aws_iam_role_policy" "allow_alpaca_invoke_trading" {
  name = "AllowAlpacaInvokeTradingServer_${var.environment}"
  
  role = aws_iam_role.lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "lambda:InvokeFunction",
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:TradingServerLambda_${var.environment}"
      }
    ]
  })
}

###############################
# Lambda Function
###############################

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}"
  output_path = "${path.module}/deployment-package.zip"

  # toss out anything that isn't runtime code
  excludes = [
    "*.tf",            # your Terraform files
    ".terraform/*",    # Terraform's state/cache dir
  ]
}

# Define the Lambda function resource
resource "aws_lambda_function" "alpaca_websocket_lambda" {
  function_name = "AlpacaWebsocketLambda_${var.environment}"
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
      ENVIRONMENT     = var.environment
      # Optionally override AWS_REGION if needed:
      # AWS_REGION = "us-east-1"
    }
  }

  # Adjust the timeout as needed (in seconds)
  timeout = 300

  # VPC configuration connecting Lambda to the same subnet and security group as the EC2 instance
  #vpc_config {
  #  subnet_ids         = ["subnet-00aa2b4ebf4b670ef"]
  #  security_group_ids = ["sg-06612080dc355b148"]
  #}
}


###############################
# (Optional) Outputs
###############################

output "lambda_function_name" {
  value = aws_lambda_function.alpaca_websocket_lambda.function_name
}

