# ======================================================================
# locals  — discover default VPC & subnets if not provided  --------------
# ======================================================================
locals {
  vpc_id = coalesce(var.vpc_id, data.aws_vpc.default.id)
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter { name = "vpc-id"   values = [local.vpc_id] }
  filter { name = "tag:aws-cdk:subnet-type" values = ["Public"] }
}

data "aws_subnets" "private" {
  filter { name = "vpc-id" values = [local.vpc_id] }
  filter { name = "tag:aws-cdk:subnet-type" values = ["Private"] }
}

locals {
  public_subnet_id   = coalesce(var.public_subnet_id, element(data.aws_subnets.public.ids, 0))
  private_subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : slice(data.aws_subnets.private.ids, 0, 2)
}