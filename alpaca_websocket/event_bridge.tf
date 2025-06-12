############################################
# 1) IAM Role so Scheduler can invoke Lambda
############################################

data "aws_iam_policy_document" "scheduler_assume_role_policy" {
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
  name               = "eventbridge-scheduler-invoke-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role_policy.json
}

resource "aws_iam_role_policy" "scheduler_lambda_invoke_policy" {
  name = "scheduler-invoke-lambda"
  role = aws_iam_role.scheduler_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.alpaca_websocket_lambda.arn
    }]
  })
}

###################################################
# 2) EventBridge Scheduler Schedule at 9 AM New York
###################################################

resource "aws_eventbridge_scheduler_schedule" "git_clone_daily_9am_est" {
  name                          = "git-clone-lambda-daily-9am-est"
  schedule_expression           = "cron(0 9 * * ? *)"
  schedule_expression_timezone  = "America/New_York"

  # OFF = strict “fire exactly at 09:00:00”
  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.alpaca_websocket_lambda.arn
    role_arn = aws_iam_role.scheduler_exec_role.arn
    # if your Lambda handler needs no payload:
    input = jsonencode({})
  }
}