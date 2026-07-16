output "github_actions_role_arn" {
  value       = aws_iam_role.github_iam_role_readonly.arn
  description = "ARN of the role assumed by GitHub Actions via OIDC"
}