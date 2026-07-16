resource "aws_iam_openid_connect_provider" "github_provider" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_iam_role_readonly" {
  name               = "github-iam-role-readonly"
  assume_role_policy = data.aws_iam_policy_document.github_policy_document_plan.json
}

data "aws_iam_policy_document" "github_policy_document_plan" {
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
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:ShamaevOleg/aws-devops-learning:*"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.github_iam_role_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}