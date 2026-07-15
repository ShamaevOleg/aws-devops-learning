resource "aws_vpc" "vpc1" {
  cidr_block = var.aws_vpc_cidr_block

  tags = {
    Name = "AWS Virtual Private Cloud 1"
  }
}

resource "aws_subnet" "subnet1" {
  vpc_id                  = aws_vpc.vpc1.id
  cidr_block              = var.aws_subnet_cidr_block
  map_public_ip_on_launch = "true"

  tags = {
    Name = "AWS Subnet 1"
  }
}

resource "aws_internet_gateway" "gw_main" {
  vpc_id = aws_vpc.vpc1.id

  tags = {
    Name = "AWS INTERNET GATEWAY 1"
  }
}

resource "aws_route_table" "route_table1" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw_main.id
  }

  tags = {
    Name = "AWS ROUTE TABLE 1"
  }
}

resource "aws_route_table_association" "rt_association1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.route_table1.id
}

resource "aws_security_group" "sg1" {
  name   = "allow_http"
  vpc_id = aws_vpc.vpc1.id

  tags = {
    Name = "AWS SECURITY GROUP 1"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.sg1.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80

  tags = {
    Name = "SECURITY GROUP INGRESS RULE ALLOW HTTP 80"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.sg1.id
  cidr_ipv4         = var.allowed_ip_subnet
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22

  tags = {
    Name = "SECURITY GROUP INGRESS RULE ALLOW SSH 22"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.sg1.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports

  tags = {
    Name = "SECURITY GROUP EGRESS RULE ALLOW ALL"
  }
}

resource "aws_instance" "nginx" {
  ami                         = data.aws_ami.ubuntu.id
  key_name                    = aws_key_pair.aws.key_name
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet1.id
  vpc_security_group_ids      = [aws_security_group.sg1.id]
  user_data_replace_on_change = true

  user_data = file("${path.module}/setup.sh")

  tags = {
    Name = "AWS INSTANCE NGINX"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.image_owner_id]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  tags = {
    Name = "AWS Amazon Machine Image Ubuntu 22.04"
  }
}

resource "aws_key_pair" "aws" {
  key_name   = "aws"
  public_key = file("~/.ssh/aws.pub")

  tags = {
    Name = "AWS KEY PAIR 1"
  }
}