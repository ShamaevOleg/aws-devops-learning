output "aws_db_instance_name" {
  value       = aws_db_instance.postgres.endpoint
  description = "Name of AWS DB instance"
}

output "aws_db_instance_secret_arn" {
  value       = aws_db_instance.postgres.master_user_secret
  description = "ARN of secret with DB password"
}