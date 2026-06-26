resource "aws_secretsmanager_secret" "runner_token" {
  name        = local.runner_token_secret_name
  description = "Ona runner token"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "runner_token" {
  secret_id     = aws_secretsmanager_secret.runner_token.id
  secret_string = var.runner_token
}

resource "aws_secretsmanager_secret" "metrics_config" {
  name_prefix = "${local.name_prefix}-metrics-"
  description = "Metrics backend configuration for the Ona runner"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "metrics_config" {
  secret_id = aws_secretsmanager_secret.metrics_config.id
  secret_string = jsonencode({
    enableMetrics = false
    url           = ""
    user          = ""
    password      = ""
  })
}
