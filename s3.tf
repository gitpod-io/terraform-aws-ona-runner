resource "aws_s3_bucket" "container_registry" {
  bucket_prefix = "${local.s3_bucket_name_prefix}-registry-"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "container_registry" {
  bucket = aws_s3_bucket.container_registry.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

moved {
  from = aws_s3_bucket_public_access_block.container_registry
  to   = aws_s3_bucket_public_access_block.container_registry[0]
}

resource "aws_s3_bucket_public_access_block" "container_registry" {
  count = var.manage_s3_bucket_public_access_block ? 1 : 0

  bucket                  = aws_s3_bucket.container_registry.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "container_registry" {
  bucket = aws_s3_bucket.container_registry.id

  rule {
    id     = "expire-buildkit-cache"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "container_registry" {
  bucket = aws_s3_bucket.container_registry.id
  policy = data.aws_iam_policy_document.container_registry_bucket.json
}

resource "aws_s3_bucket" "logs" {
  bucket_prefix = "${local.s3_bucket_name_prefix}-logs-"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

moved {
  from = aws_s3_bucket_public_access_block.logs
  to   = aws_s3_bucket_public_access_block.logs[0]
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = var.manage_s3_bucket_public_access_block ? 1 : 0

  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-environment-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json
}

resource "aws_s3_bucket" "agent" {
  bucket_prefix = "${local.s3_bucket_name_prefix}-agent-"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "agent" {
  bucket = aws_s3_bucket.agent.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

moved {
  from = aws_s3_bucket_public_access_block.agent
  to   = aws_s3_bucket_public_access_block.agent[0]
}

resource "aws_s3_bucket_public_access_block" "agent" {
  count = var.manage_s3_bucket_public_access_block ? 1 : 0

  bucket                  = aws_s3_bucket.agent.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "agent" {
  bucket = aws_s3_bucket.agent.id

  rule {
    id     = "expire-workflow-action-support-bundles"
    status = "Enabled"

    filter {
      prefix = "workflow-action-support-bundles/"
    }

    expiration {
      days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "expire-agent-data"
    status = "Enabled"

    filter {}

    expiration {
      days = 360
    }
  }
}

resource "aws_s3_bucket_policy" "agent" {
  bucket = aws_s3_bucket.agent.id
  policy = data.aws_iam_policy_document.agent_bucket.json
}

data "aws_iam_policy_document" "container_registry_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.container_registry.arn,
      "${aws_s3_bucket.container_registry.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "DenyReadsExceptS3AccessRole"
    effect  = "Deny"
    actions = ["s3:GetObject", "s3:GetObjectVersion"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = ["${aws_s3_bucket.container_registry.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.s3_access.arn]
    }
  }
}

data "aws_iam_policy_document" "logs_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "agent_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.agent.arn,
      "${aws_s3_bucket.agent.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
