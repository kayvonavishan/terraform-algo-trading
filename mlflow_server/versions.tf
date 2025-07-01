terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = ">= 5.90" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.13.0"
}
  }
}

provider "aws" {
  region = var.aws_region
}