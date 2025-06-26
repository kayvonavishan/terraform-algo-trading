# dns.tf

# Look up the private Zone for your Aurora cluster
data "aws_route53_zone" "rds_cluster" {
  name         = "cluster-cjyv8mtxzsqc.us-east-1.rds.amazonaws.com"
  private_zone = true
}

# Associate it with your VPC
resource "aws_route53_zone_association" "rds" {
  zone_id    = data.aws_route53_zone.rds_cluster.zone_id
  vpc_id     = local.vpc_id
  vpc_region = var.aws_region
}
