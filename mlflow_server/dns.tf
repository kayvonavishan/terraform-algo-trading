# 1) Look up the private hosted zone for your cluster.
#    The zone name is the part after “cluster-” in your endpoint:
#
#    mlflow-aurora.cluster-<ZONEID>.us-east-1.rds.amazonaws.com
#
#    Cloud Map only publishes the ZONEID part, so we use:
#    "<ZONEID>.us-east-1.rds.amazonaws.com"
data "aws_route53_zone" "rds_cluster" {
  name         = "cjyv8mtxzsqc.us-east-1.rds.amazonaws.com"
  private_zone = true
}

# 2) Associate that zone with your VPC
resource "aws_route53_zone_association" "rds_cluster" {
  zone_id     = data.aws_route53_zone.rds_cluster.zone_id
  vpc_id      = local.vpc_id
  vpc_region  = var.aws_region
}
