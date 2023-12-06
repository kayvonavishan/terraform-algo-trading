terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "model_training_instance" {
  # ami           = "ami-0ac1f653c5b6af751"
  # ami           = "ami-06edc089743b8b36a"
  ami           = "ami-0abb2a5b978c7cce0"
  # instance_type = "t3.large"
  instance_type = "g4dn.xlarge"
  key_name      = "training-server"
  subnet_id     = "subnet-00aa2b4ebf4b670ef"
  user_data     = file("init.sh")
  vpc_security_group_ids  = [
    "sg-015df5d5e01209a7d",
    "sg-0d8e253c9ef45207d",
    "sg-0bd7faa83cd5552e8"
  ]
  tags = {
    Name = "GPU Training Server"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "vol-0362d4ea505b3444d"
  instance_id = aws_instance.model_training_instance.id
}