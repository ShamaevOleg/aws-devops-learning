output "vpc_id" {
  value       = aws_vpc.main_vpc.id
  description = "ID of main AWS VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public_subnet[*].id
  description = "IDs of public subnets"
}

output "private_subnet_ids" {
  value       = aws_subnet.private_subnet[*].id
  description = "IDs of private subnets"
}

output "vpc_cidr" {
  value       = aws_vpc.main_vpc.cidr_block
  description = "CIDR of main AWS VPC"
}