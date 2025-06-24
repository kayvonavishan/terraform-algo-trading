resource "aws_s3_bucket" "artifacts" {
  bucket        = "algo-experiments"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Fetch every route table in the VPC
data "aws_route_tables" "all" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Stand up the S3 Gateway endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id        = local.vpc_id
  service_name  = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = data.aws_route_tables.all.ids

  # no policy block = full S3 access
}
