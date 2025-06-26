resource "random_password" "db" {
  length  = 16
  special = false
}

resource "aws_db_subnet_group" "mlflow" {
  name       = "mlflow-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_security_group" "rds" {
  name   = "mlflow-rds"
  vpc_id = local.vpc_id

  ingress {
    description     = "Postgres from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_rds_cluster" "mlflow" {
  cluster_identifier = "mlflow-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "16.6"
  database_name      = "mlflow"
  master_username    = "mlflow"
  master_password    = random_password.db.result

  serverlessv2_scaling_configuration {
    min_capacity             = 0
    max_capacity             = 2
    seconds_until_auto_pause = 300
  }

  db_subnet_group_name   = aws_db_subnet_group.mlflow.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  storage_encrypted      = true
}

resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier = aws_rds_cluster.mlflow.id

  # Aurora Serverless v2 uses the special class below
  instance_class     = "db.serverless"

  # Keep engine/engine_version aligned with the cluster
  engine             = aws_rds_cluster.mlflow.engine
  engine_version     = aws_rds_cluster.mlflow.engine_version

  publicly_accessible = false
  db_subnet_group_name = aws_db_subnet_group.mlflow.name
  vpc_security_group_ids = [aws_security_group.rds.id]
}