locals {
  roles = {
    readonly = { sub = "repo:ShamaevOleg/aws-devops-learning:*", test = "StringLike" }
    apply    = { sub = "repo:ShamaevOleg/aws-devops-learning:environment:production", test = "StringEquals" }
  }
}

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

resource "aws_iam_role_policy_attachment" "vpcFullAccess" {
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