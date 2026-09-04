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

resource "aws_secretsmanager_secret" "internal_llm_tls" {
  count = var.restrict_ingress ? 1 : 0

  name_prefix = "${local.name_prefix}-llm-tls-"
  description = "Self-signed TLS certificate and private key for the runner's internal LLM proxy"
  tags        = local.common_tags
}
