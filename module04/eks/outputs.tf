output "aws_eks_cluster_name" {
  value       = aws_eks_cluster.eks_cluster_example.name
  description = "Name of AWS EKS cluster"
}

output "aws_eks_cluster_endpoint" {
  value       = aws_eks_cluster.eks_cluster_example.endpoint
  description = "Endpoint of AWS EKS cluster"
}

output "aws_eks_iam_openid_connect_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "ARN of AWS EKS OIDC provider"
}

output "aws_eks_tls_certificate_issuer_url" {
  value       = data.tls_certificate.eks_oidc.url
  description = "URL of TLS certificate's issuer in EKS"
}