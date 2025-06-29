resource "random_password" "db" {
  length  = 16
  special = false
}

resource "aws_db_subnet_group" "mlflow" {
  name       = "mlflow-db-subnets"
  subnet_ids = local.public_subnet_ids
}

resource "aws_db_subnet_group" "mlflow_public" {
  name       = "mlflow-db-public-subnets"
  subnet_ids = local.public_subnet_ids
}

resource "aws_security_group" "rds" {
  name   = "mlflow-rds"
  vpc_id = local.vpc_id

  ingress {
    description = "Postgres from my laptop"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # either lock down to your IP, e.g. ["1.2.3.4/32"],
    # or use 0.0.0.0/0 if you really need globally open:
    cidr_blocks = var.allowed_cidr_blocks  # set this to your client CIDR
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
  #master_password    = random_password.db.result
  master_password    = "mypw123321"

  serverlessv2_scaling_configuration {
    min_capacity             = 0
    max_capacity             = 2
    seconds_until_auto_pause = 300
  }

  db_subnet_group_name   = aws_db_subnet_group.mlflow_public.name
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

  publicly_accessible = true
  db_subnet_group_name = aws_db_subnet_group.mlflow_public.name
}