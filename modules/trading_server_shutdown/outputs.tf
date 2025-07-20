# Trading Server Shutdown Module Outputs

output "lambda_function_name" {
  description = "Name of the shutdown lambda function"
  value       = aws_lambda_function.shutdown_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the shutdown lambda function"
  value       = aws_lambda_function.shutdown_lambda.arn
}

output "schedule_rule_name" {
  description = "Name of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.shutdown_schedule.name
}