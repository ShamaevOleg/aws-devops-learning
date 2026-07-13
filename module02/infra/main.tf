resource "aws_vpc" "main" {
  cidr_block = var.aws_vpc_cidr_block
}

resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.aws_subnet_cidr_block
  map_public_ip_on_launch = "true"

}

resource "aws_internet_gateway" "gw_main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.cidr_all
    gateway_id = aws_internet_gateway.gw_main.id
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "main" {
  name        = "allow_http"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = var.cidr_all
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = var.allowed_ip_list
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = var.cidr_all
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_instance" "example" {
  ami           = data.aws_ami.ubuntu.id
  key_name = "aws"
  instance_type = var.instance_type
  subnet_id = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.main.id]

  user_data = file("./setup.sh")
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "image-id"
    values = [var.image_id]
  }
}

resource "aws_key_pair" "aws" {
  key_name = "aws"
  public_key = file(var.public_key_path)
}