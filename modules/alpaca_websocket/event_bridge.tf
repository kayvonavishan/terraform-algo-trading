###############################
# 1) IAM Role for Scheduler (conditional)
###############################

data "aws_iam_policy_document" "scheduler_assume_role" {
  count = var.enable_eventbridge ? 1 : 0
  
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
  count = var.enable_eventbridge ? 1 : 0
  
  name               = "eventbridge-scheduler-invoke-lambda-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role[0].json
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  count = var.enable_eventbridge ? 1 : 0
  
  name = "scheduler-invoke-lambda-${var.environment}"
  role = aws_iam_role.scheduler_exec_role[0].id

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
# 2) Scheduler: every day at 9AM America/New_York (conditional)
#############################################

resource "aws_scheduler_schedule" "alpaca_websocket_daily_9am_est" {
  count = var.enable_eventbridge ? 1 : 0
  
  name                         = "alpaca-websocket-lambda-daily-9am-est-${var.environment}"
  schedule_expression          = "cron(30 8 ? * MON-FRI *)"
  schedule_expression_timezone = "America/New_York"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.alpaca_websocket_lambda.arn
    role_arn = aws_iam_role.scheduler_exec_role[0].arn
    input    = jsonencode({})      # empty JSON payload
  }
}
