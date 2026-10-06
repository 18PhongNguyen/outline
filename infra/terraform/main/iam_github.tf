data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  gh_subs = {
    deploy = "repo:${var.github_repo}:ref:refs/heads/main"
    plan   = "repo:${var.github_repo}:pull_request"
    apply  = "repo:${var.github_repo}:environment:production"
  }
}

data "aws_iam_policy_document" "gh_assume" {
  for_each = local.gh_subs

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "gh_deploy" {
  name               = "outline-gh-deploy"
  assume_role_policy = data.aws_iam_policy_document.gh_assume["deploy"].json
}

resource "aws_iam_role" "gh_plan" {
  name               = "outline-gh-plan"
  assume_role_policy = data.aws_iam_policy_document.gh_assume["plan"].json
}

resource "aws_iam_role" "gh_apply" {
  name               = "outline-gh-apply"
  assume_role_policy = data.aws_iam_policy_document.gh_assume["apply"].json
}

data "aws_iam_policy_document" "gh_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for r in aws_ecr_repository.this : r.arn]
  }

  statement {
    sid       = "DeployBucketObjects"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.deploy_bucket}/*"]
  }

  statement {
    sid       = "DeployBucketList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.deploy_bucket}"]
  }

  statement {
    sid     = "SendCommand"
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.region}:${local.account_id}:instance/${aws_instance.outline.id}",
      "arn:aws:ssm:${var.region}::document/AWS-RunShellScript",
    ]
  }

  statement {
    sid       = "ReadCommand"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gh_deploy" {
  name   = "outline-gh-deploy"
  role   = aws_iam_role.gh_deploy.id
  policy = data.aws_iam_policy_document.gh_deploy.json
}

resource "aws_iam_role_policy_attachment" "gh_plan_readonly" {
  role       = aws_iam_role.gh_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "gh_plan" {
  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/*"]
  }

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.state_bucket}"]
  }

  statement {
    sid       = "DecryptSsm"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "gh_plan" {
  name   = "outline-gh-plan"
  role   = aws_iam_role.gh_plan.id
  policy = data.aws_iam_policy_document.gh_plan.json
}

resource "aws_iam_role_policy_attachment" "gh_apply_admin" {
  role       = aws_iam_role.gh_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
