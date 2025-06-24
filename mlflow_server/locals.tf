data "aws_vpc" "default" {
  default = true
}

locals {
  vpc_id = coalesce(var.vpc_id, data.aws_vpc.default.id)
}

# Gather all subnets in the VPC
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Inspect each subnet for public IP assignment
data "aws_subnet" "each" {
  for_each = toset(data.aws_subnets.all.ids)
  id       = each.value
}

locals {
  public_subnet_ids = [
    for s in data.aws_subnet.each : s.id if s.map_public_ip_on_launch
  ]

  public_subnet_id = var.public_subnet_id != null ? var.public_subnet_id : (
    length(local.public_subnet_ids) > 0 ? local.public_subnet_ids[0] :
    error("No public subnet found in VPC ${local.vpc_id}. Please set var.public_subnet_id.")
  )

  private_subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : (
    aws_subnet.private[*].id
  )
}