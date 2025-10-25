# Alpaca WebSocket Module Outputs

output "instance_id" {
  description = "ID of the alpaca websocket instance"
  value       = aws_instance.alpaca_instance.id
}

output "instance_public_ip" {
  description = "Public IP of the alpaca websocket instance"
  value       = aws_instance.alpaca_instance.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the alpaca websocket instance"
  value       = aws_instance.alpaca_instance.private_ip
}

output "instance_name" {
  description = "Name tag of the alpaca websocket instance"
  value       = aws_instance.alpaca_instance.tags.Name
}

output "lambda_function_name" {
  description = "Name of the Alpaca websocket Lambda function"
  value       = aws_lambda_function.alpaca_websocket_lambda.function_name
}

output "lambda_role_name" {
  description = "IAM role name used by the Alpaca websocket Lambda"
  value       = aws_iam_role.lambda_role.name
}
