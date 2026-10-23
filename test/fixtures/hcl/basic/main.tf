terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = { source = "hashicorp/random" }
  }
  required_version = ">= 1.5"
}

provider "aws" {
  region = "us-east-1" # trailing comment
  profile = "dev" // another
  max_retries = 5
  skip_x = true
  ratio = 1.50
  big = 12345678.5
  tiny = 0.0005
}

resource "aws_instance" "web" {
  ami           = "ami-0abc"
  instance_type = "t3.micro"
  count = 2,
  tags = {
    Name = "web"
  }
  user_data = "line1\nline2 \"quoted\" back\\slash \$dollar"
  provider = aws.west
}

data "aws_ami" "latest" {
  most_recent = true
  owners = ["amazon"]
}

module "network" {
  source = "./modules/network"
  cidr = "10.0.0.0/16"
}

variable "region" {
  type = string
  default = "us-east-1"
}

output "ip" {
  value = aws_instance.web.public_ip
  description = "the ip"
}
