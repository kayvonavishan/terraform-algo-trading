###############################
# Package Lambda Code
###############################

data "archive_file" "shutdown_lambda_package" {
  type        = "zip"
  source_dir  = "."
  output_path = "./shutdown-deployment-package.zip"

  excludes = [
    "*.tf",
    ".terraform/*"
  ]
}

###############################
# IAM Role and Policy for Shutdown Lambda
###############################

data "aws_iam_policy_document" "shutdown_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "shutdown_lambda_role" {
  name               = "trading_server_shutdown_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.shutdown_assume_role.json
}

resource "aws_iam_policy" "shutdown_lambda_policy" {
  name        = "trading_server_shutdown_lambda_policy"
  description = "Allow Lambda to describe and stop EC2 instances and write logs"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:StopInstances"
      ],
      "Resource": "*"
    },
    {
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

resource "aws_iam_role_policy_attachment" "shutdown_policy_attach" {
  role       = aws_iam_role.shutdown_lambda_role.name
  policy_arn = aws_iam_policy.shutdown_lambda_policy.arn
}

###############################
# Lambda Function
###############################

resource "aws_lambda_function" "shutdown_lambda" {
  function_name = "TradingServerShutdownLambda"
  role          = aws_iam_role.shutdown_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"

  filename         = data.archive_file.shutdown_lambda_package.output_path
  source_code_hash = data.archive_file.shutdown_lambda_package.output_base64sha256

  #environment {
  #  variables = {
  #    AWS_REGION = var.aws_region
  #  }
  #}

  timeout = 60
  publish = true
}

###############################
# EventBridge Schedule Rule
###############################

resource "aws_cloudwatch_event_rule" "shutdown_schedule" {
  name                = "trading-server-shutdown-schedule"
  description         = "Daily shutdown of trading servers at 4:05 PM EST"
  schedule_expression = "cron(5 21 * * ? *)"
}

resource "aws_cloudwatch_event_target" "shutdown_target" {
  rule      = aws_cloudwatch_event_rule.shutdown_schedule.name
  target_id = "invoke-shutdown-lambda"
  arn       = aws_lambda_function.shutdown_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shutdown_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.shutdown_schedule.arn
}