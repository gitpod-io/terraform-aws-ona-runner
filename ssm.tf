resource "aws_ssm_parameter" "runner_config" {
  name  = local.runner_config_key
  type  = "SecureString"
  value = local.runner_config
  tags  = local.common_tags
}
