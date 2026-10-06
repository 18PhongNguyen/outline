data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "outline-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_ro" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "ec2_inline" {
  statement {
    sid       = "ObjectsRW"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.attachments_bucket}/*", "arn:aws:s3:::${local.backups_bucket}/*"]
  }

  statement {
    sid       = "ListRW"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.attachments_bucket}", "arn:aws:s3:::${local.backups_bucket}"]
  }

  statement {
    sid       = "DeployRead"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.deploy_bucket}/*"]
  }

  statement {
    sid       = "DeployList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.deploy_bucket}"]
  }

  statement {
    sid     = "ReadParams"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:*:${local.account_id}:parameter/outline/*",
      "arn:aws:ssm:*:${local.account_id}:parameter/outline",
    ]
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

resource "aws_iam_role_policy" "ec2_inline" {
  name   = "outline-ec2-inline"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_inline.json
}

resource "aws_iam_instance_profile" "outline" {
  name = "outline-ec2"
  role = aws_iam_role.ec2.name
}
