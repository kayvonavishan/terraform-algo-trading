terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws      = { source = "hashicorp/aws",      version = ">= 5.90" }
    random   = { source = "hashicorp/random",   version = "~> 3.6" }
    template = { source = "hashicorp/template", version = "~> 2.3" }
  }
}

provider "aws" {
  region = var.aws_region
}