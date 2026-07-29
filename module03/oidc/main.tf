locals {
  roles = {
    readonly = { sub = "repo:ShamaevOleg/aws-devops-learning:*", test = "StringLike" }
    apply    = { sub = "repo:ShamaevOleg/aws-devops-learning:environment:production", test = "StringEquals" }
    push     = { sub = "repo:ShamaevOleg/aws-devops-learning:ref:refs/heads/main", test = "StringEquals" }
    website  = { sub = "repo:ShamaevOleg/website:*", test = "StringLike" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_openid_connect_provider" "github_provider" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_iam_role_readonly" {
  name               = "github-iam-role-readonly"
  assume_role_policy = data.aws_iam_policy_document.trust["readonly"].json
}

resource "aws_iam_role" "github_iam_role_apply" {
  name               = "github-iam-role-apply"
  assume_role_policy = data.aws_iam_policy_document.trust["apply"].json
}

resource "aws_iam_role" "github_iam_role_ecr_push_images" {
  name               = "github-iam-role-ecr-push-images"
  assume_role_policy = data.aws_iam_policy_document.trust["push"].json
}

resource "aws_iam_role" "github_iam_role_website_ecr_push_images" {
  name               = "github-iam-role-website-ecr-push-images"
  assume_role_policy = data.aws_iam_policy_document.trust["website"].json
}

data "aws_iam_policy_document" "trust" {
  for_each = local.roles
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_provider.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = each.value.test
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value.sub]
    }
  }
}

data "aws_iam_policy_document" "tfstate_access" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::oleg-tfstate-initial/*"] # объекты внутри бакета
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::oleg-tfstate-initial"] # сам бакет
  }
}

resource "aws_iam_policy" "tfstate" {
  name        = "tfstate-access"
  description = "Read/write access to Terraform state in S3"
  policy      = data.aws_iam_policy_document.tfstate_access.json
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.github_iam_role_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "vpc_full_access" {
  role       = aws_iam_role.github_iam_role_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}

resource "aws_iam_role_policy_attachment" "tfstate_readonly" {
  role       = aws_iam_role.github_iam_role_readonly.name
  policy_arn = aws_iam_policy.tfstate.arn
}

resource "aws_iam_role_policy_attachment" "tfstate_apply" {
  role       = aws_iam_role.github_iam_role_apply.name
  policy_arn = aws_iam_policy.tfstate.arn
}

data "aws_iam_policy_document" "ecr_create_repo_policy" {
  statement {
    effect = "Allow"
    actions = ["ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:TagResource",
      "ecr:GetRepositoryPolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:ListTagsForResource",
      "ecr:UntagResource",
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepository",
      "ecr:DeleteLifecyclePolicy",
      "ecr:DeleteRepositoryPolicy"
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }
}

data "aws_iam_policy_document" "ecr_push_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "website_ecr_push_policy" {
  statement {
    sid    = "PushPull"
    effect = "Allow"
    actions = [
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/website/*"]
  }
  statement {
    sid       = "AuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecr_manage_policy" {
  name   = "ecr-manage-policy"
  policy = data.aws_iam_policy_document.ecr_create_repo_policy.json
}

resource "aws_iam_policy" "ecr_push_policy" {
  name   = "ecr-push-policy"
  policy = data.aws_iam_policy_document.ecr_push_policy.json
}

resource "aws_iam_policy" "website_ecr_push_policy" {
  name   = "website-ecr-push-policy"
  policy = data.aws_iam_policy_document.website_ecr_push_policy.json
}

resource "aws_iam_role_policy_attachment" "ecr_manage_policy_role_attach" {
  role       = aws_iam_role.github_iam_role_apply.name
  policy_arn = aws_iam_policy.ecr_manage_policy.arn
}

resource "aws_iam_role_policy_attachment" "ecr_push_policy_role_attach" {
  role       = aws_iam_role.github_iam_role_ecr_push_images.name
  policy_arn = aws_iam_policy.ecr_push_policy.arn
}

resource "aws_iam_role_policy_attachment" "website_ecr_push_policy_role_attach" {
  role       = aws_iam_role.github_iam_role_website_ecr_push_images.name
  policy_arn = aws_iam_policy.website_ecr_push_policy.arn
}
