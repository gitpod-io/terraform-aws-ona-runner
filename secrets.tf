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
