data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "oleg-tfstate-initial"
    key    = "network/terraform.tfstate"
    region = "eu-west-2"
  }
}

data "terraform_remote_state" "rds" {
  backend = "s3"
  config = {
    bucket = "oleg-tfstate-initial"
    key    = "module05/rds/terraform.tfstate"
    region = "eu-west-2"
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "eks_cluster_role"
  assume_role_policy = data.aws_iam_policy_document.eks_trust.json
}

resource "aws_iam_role" "eks_node_role" {
  name               = "eks_node_role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

}

data "aws_iam_policy_document" "eks_trust" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_role_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_role_attachment" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.eks_node_role.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "eks_cluster_example" {
  name     = "eks_cluster_example"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.eks_cluster_version
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = data.terraform_remote_state.network.outputs.public_subnet_ids
    public_access_cidrs     = [var.allowed_ip_for_kubectl]
  }
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_role_attachment]

  tags = {
    Name = "AWS EKS cluster for learning"
  }
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.eks_cluster_example.name
  principal_arn = data.aws_caller_identity.current.arn
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.eks_cluster_example.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.admin.principal_arn

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_node_group" "eks_example_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster_example.name
  node_group_name = "example_node_group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = data.terraform_remote_state.network.outputs.public_subnet_ids
  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }
  instance_types = ["c7i-flex.large", "m7i-flex.large", "t3.small"]
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"
  depends_on     = [aws_iam_role_policy_attachment.eks_node_role_attachment]
}

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.eks_cluster_example.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.eks_cluster_example.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "eso_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["${data.terraform_remote_state.rds.outputs.aws_db_instance_secret_arn}*"]
  }
}

resource "aws_iam_role" "eso" {
  name               = "external-secrets-operator"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
}

resource "aws_iam_policy" "eso_secrets" {
  name   = "eso-read-rds-secret"
  policy = data.aws_iam_policy_document.eso_secrets.json
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso_secrets.arn
}
