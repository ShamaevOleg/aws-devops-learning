output "github_actions_role_arn" {
  value       = aws_iam_role.github_iam_role_readonly.arn
  description = "ARN of the role assumed by GitHub Actions via OIDC for only tf plan"
}

output "github_actions_role_apply_arn" {
  value       = aws_iam_role.github_iam_role_apply.arn
  description = "ARN of the role assumed by GitHub Actions via OIDC for tf apply"
}