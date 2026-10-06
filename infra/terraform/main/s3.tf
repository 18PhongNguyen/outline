locals {
  account_id         = data.aws_caller_identity.current.account_id
  attachments_bucket = "outline-attachments-${local.account_id}"
  backups_bucket     = "outline-backups-${local.account_id}"
  deploy_bucket      = "outline-deploy-${local.account_id}"
  state_bucket       = "outline-tfstate-${local.account_id}"
  ecr_registry       = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"

  buckets = {
    attachments = local.attachments_bucket
    backups     = local.backups_bucket
    deploy      = local.deploy_bucket
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = each.value
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_cors_configuration" "attachments" {
  bucket = aws_s3_bucket.this["attachments"].id

  cors_rule {
    allowed_origins = ["https://${var.domain}"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.this["backups"].id

  rule {
    id     = "expire-14d"
    status = "Enabled"

    filter {}

    expiration {
      days = 14
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "deploy" {
  bucket = aws_s3_bucket.this["deploy"].id

  rule {
    id     = "expire-30d"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}
