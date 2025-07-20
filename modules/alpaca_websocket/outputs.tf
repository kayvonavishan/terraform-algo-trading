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