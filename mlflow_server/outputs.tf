output "mlflow_ui" {
  description = "URL to open MLflow UI"
  value       = "http://${aws_instance.mlflow.public_ip}:${var.mlflow_port}"
}

output "db_password" {
  sensitive   = true
  value       = random_password.db.result
}
