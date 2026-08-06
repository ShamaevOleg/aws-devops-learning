data "aws_availability_zones" "available" {
  state = "available"
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "oleg-tfstate-initial"
    key    = "network/terraform.tfstate"
    region = "eu-west-2"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "main-db-subnet-group"

  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_ingress_from_vpc" {
  security_group_id = aws_security_group.db_sg.id
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = data.terraform_remote_state.network.outputs.vpc_cidr
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