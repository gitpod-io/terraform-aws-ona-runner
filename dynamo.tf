resource "aws_dynamodb_table" "resources" {
  name         = "${local.name_prefix}-reconciler"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  table_class  = "STANDARD"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}

resource "aws_dynamodb_resource_policy" "resources" {
  count        = var.disable_resource_policies ? 0 : 1
  resource_arn = aws_dynamodb_table.resources.arn
  policy       = data.aws_iam_policy_document.dynamodb_resource.json
}

data "aws_iam_policy_document" "dynamodb_resource" {
  statement {
    sid    = "DenyReadsExceptRunnerTaskRole"
    effect = "Deny"

    actions = [
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:PartiQLSelect",
      "dynamodb:Scan",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [aws_dynamodb_table.resources.arn]

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.ecs_task.arn]
    }
  }
}
