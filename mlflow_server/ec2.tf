resource "aws_security_group" "ec2" {
  name   = "mlflow-ec2"
  vpc_id = local.vpc_id

  ingress { from_port = 22 to_port = 22 protocol = "tcp" cidr_blocks = var.allowed_cidr_blocks }
  ingress { from_port = var.mlflow_port to_port = var.mlflow_port protocol = "tcp" cidr_blocks = var.allowed_cidr_blocks }
  egress  { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_instance" "mlflow" {
  ami                    = local.mlflow_ami_id
  instance_type          = var.instance_type
  subnet_id              = local.public_subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/mlflow_user_data.sh.tpl", {
    db_endpoint  = aws_rds_cluster.mlflow.endpoint,
    db_password  = random_password.db.result,
    bucket_name  = aws_s3_bucket.artifacts.bucket,
    mlflow_port  = var.mlflow_port
  })

  tags = { Name = "mlflow-server" }
}