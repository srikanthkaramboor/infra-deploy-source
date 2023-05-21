#source
resource "aws_instance" "test-ec2-machin" {
  ami           = "ami-0263e4deb427da90e"
  instance_type = "t3.micro"

}

resource "aws_vpc" "test-vpc" {
  cidr_block = "10.0.0.0/16"
  tags ={
    Name = "production"
  }
  }

  resource "aws_vpc" "test2-vpc" {
  cidr_block = "10.1.0.0/16"
  tags ={
    Name = "dev"
  }
  }

resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.test-vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "prod-subnet"
  }
}

resource "aws_subnet" "subnet-2" {
  vpc_id     = aws_vpc.test2-vpc.id
  cidr_block = "10.1.1.0/24"

  tags = {
    Name = "Main"
  }
}

resource "aws_subnet" "subnet-3" {
  vpc_id     = aws_vpc.test2-vpc.id
  cidr_block = "10.1.0.0/24"

  tags = {
    Name = "Main"
  }
}

terraform {
  backend "s3" {
    bucket = "sk-tf1-storage-bk"
    key = "terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "dynamodb-state-locking"
  }
}
#TEST it later
resource "aws_lb" "front_end" {
  name               = "front-end-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.main_sg.id]
  subnets            = aws_subnet.public_subnets.*.id

  enable_deletion_protection = false

  tags = {
    Environment = "test"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.front_end.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_end.arn
  }
}

resource "aws_lb_target_group" "front_end" {
  name     = "front-end-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "front_end" {
  count            = length(aws_subnet.public_subnets)
  target_group_arn = aws_lb_target_group.front_end.arn
  target_id        = aws_instance.front_end[count.index].id
  port             = 80
}

#ec2.tf
data "aws_ami" "amazon_linux_2" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "front_end" {
  count                       = length(aws_subnet.public_subnets)
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.nano"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.public_subnets[count.index].id

  vpc_security_group_ids = [
    aws_security_group.main_sg.id,
  ]

  user_data = <<-EOF
    #!/bin/bash
    sudo su
    yum update -y
    yum install -y httpd.x86_64
    systemctl start httpd.service
    systemctl enable httpd.service
    echo “Hello World from $(hostname -f)” > /var/www/html/index.html
        EOF

  tags = {
    Name = "HelloWorld_${count.index + 1}"
  }
}
#main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.5.0"
    }
  }

  required_version = ">= 0.14.9"
}

# provider "aws" {
#   profile = "default"
#   region  = "us-east-1"
# }

#outputs.tf
output "lb_dns_url" {
    value = aws_lb.front_end.dns_name
}


variable "main_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_cidr_blocks" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

#variables.tf
variable "private_cidr_blocks" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = var.main_cidr_block

  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_cidr_blocks)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_cidr_blocks[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet_${count.index + 1}"
  }
}

resource "aws_security_group" "main_sg" {
  name        = "allow_connection"
  description = "Allow HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public_route"
  }
}

resource "aws_route_table_association" "public_route_association" {
  count          = length(var.public_cidr_blocks)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route.id
}