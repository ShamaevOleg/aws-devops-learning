output "aws_eks_cluster_name" {
  value       = aws_eks_cluster.eks_cluster_example.name
  description = "Name of AWS EKS cluster"
}

output "aws_eks_cluster_endpoint" {
  value       = aws_eks_cluster.eks_cluster_example.endpoint
  description = "Endpoint of AWS EKS cluster"
}
