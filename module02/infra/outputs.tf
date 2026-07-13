output vpc_instance_id {
  value = aws_vpc.main.id
  description = "VPC instance ID"
}

output aws_instance_public_ip {
  value = ["${aws_instance.example.*.public_ip}"]
  description = "Instance instance ID"
}