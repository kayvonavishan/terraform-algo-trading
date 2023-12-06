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

resource "aws_ebs_volume" "model_training_volume" {
  availability_zone = "us-east-1a"
  size              = 1
  type              = "gp3"

  tags = {
    Name = "GPU Training Server"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow ssh from inbound traffic"
  vpc_id      = "vpc-0664c3730bd2e574b"

  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group" "allow_jupyter" {
  name        = "allow_jupyter"
  description = "Allow jupyter from inbound traffic"
  vpc_id      = "vpc-0664c3730bd2e574b"

  ingress {
    description = "Http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Https from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Custom port from VPC"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_jupyter"
  }
}

resource "aws_security_group" "open_outbound_traffic" {
  name        = "open_outbound_traffic"
  description = "Open outbound traffic"
  vpc_id      = "vpc-0664c3730bd2e574b"

  egress {
    description = "Open outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Open outbound traffic"
  }
}
