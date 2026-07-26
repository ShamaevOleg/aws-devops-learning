output "aws_ecr_repository_urls" {
  value       = { for k, repo in aws_ecr_repository.website : k => repo.repository_url }
  description = "URLs of the ECR repositories, keyed by name"
}