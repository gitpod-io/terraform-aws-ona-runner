module "runner" {
  source = "../.."

  runner_id         = var.runner_id
  runner_token      = var.runner_token
  api_endpoint      = var.api_endpoint
  runner_name       = var.runner_name
  vpc_id            = var.vpc_id
  runner_subnet_ids = var.runner_subnet_ids
  restrict_ingress  = true

  pre_created_iam_roles             = var.pre_created_iam_roles
  environment_instance_profile_name = var.environment_instance_profile_name

  proxy_config           = var.proxy_config
  custom_ca_trust_bundle = var.custom_ca_trust_bundle
}
