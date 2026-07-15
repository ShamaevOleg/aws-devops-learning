output "vpc_instance_id" {
  value       = aws_vpc.vpc1.id
  description = "VPC instance ID"
}

output "aws_instance_public_ip" {
  value       = aws_instance.nginx.public_ip
  description = "Instance instance ID"
}