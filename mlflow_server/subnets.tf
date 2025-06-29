# Grab two AZ names
data "aws_availability_zones" "available" {
  state = "available"
}

# Create exactly two private subnets
resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = local.vpc_id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "mlflow-private-${count.index}"
  }
}
