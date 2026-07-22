output "aws_ecr_repository_url" {
  value       = aws_ecr_repository.website_backend.repository_url
  description = "URL of the AWS ECR for website backend"
}