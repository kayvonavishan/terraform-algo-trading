###############################
# 1) IAM Role for Scheduler
###############################

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "scheduler_exec_role" {
  name               = "eventbridge-scheduler-invoke-lambda"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  name = "scheduler-invoke-lambda"
  role = aws_iam_role.scheduler_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.alpaca_websocket_lambda.arn
      }
    ]
  })
}

#############################################
# 2) Scheduler: every day at 9AM America/New_York
#############################################

resource "aws_scheduler_schedule" "alpaca_websocket_daily_9am_est" {
  name                         = "alpaca-websocket-lambda-daily-9am-est"
  schedule_expression          = "cron(30 8 ? * MON-FRI *)"
  schedule_expression_timezone = "America/New_York"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.alpaca_websocket_lambda.arn
    role_arn = aws_iam_role.scheduler_exec_role.arn
    input    = jsonencode({})      # empty JSON payload
  }
}
