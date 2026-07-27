data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc_for_rds" {
  cidr_block = var.cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "subnet_for_rds" {
  count  = 2
  vpc_id = aws_vpc.vpc_for_rds.id

  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "subnet-for-rds-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "main-db-subnet-group"

  subnet_ids = aws_subnet.subnet_for_rds[*].id
}

resource "aws_security_group" "app_sg" {
  name   = "app-sg"
  vpc_id = aws_vpc.vpc_for_rds.id
}

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.vpc_for_rds.id
}

resource "aws_vpc_security_group_ingress_rule" "db_ingress_5432" {
  security_group_id            = aws_security_group.db_sg.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app_sg.id
}

resource "aws_vpc_security_group_egress_rule" "db_egress_allow_all" {
  security_group_id = aws_security_group.db_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_instance" "postgres" {
  identifier        = "db-instance-for-backend"
  engine            = "postgres"
  engine_version    = var.db_engine_version
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name                     = "remni"
  username                    = "postgres"
  manage_master_user_password = true # password will be generated and stored by RDS

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  publicly_accessible = false
  skip_final_snapshot = true # for develop stand
  storage_encrypted   = true
}