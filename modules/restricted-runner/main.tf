module "runner" {
  source = "../.."

  runner_id                            = var.runner_id
  runner_token                         = var.runner_token
  runner_name                          = var.runner_name
  resource_name_prefix                 = var.resource_name_prefix
  api_endpoint                         = var.api_endpoint
  vpc_id                               = var.vpc_id
  runner_subnet_ids                    = var.runner_subnet_ids
  runner_size                          = var.runner_size
  cache_engine                         = var.cache_engine
  runner_image                         = var.runner_image
  assign_public_ip                     = var.assign_public_ip
  restrict_ingress                     = true
  internal_llm_proxy_port              = var.internal_llm_proxy_port
  manage_s3_bucket_public_access_block = var.manage_s3_bucket_public_access_block
  runner_template_build_version        = var.runner_template_build_version
  proxy_config                         = var.proxy_config
  custom_ca_trust_bundle               = var.custom_ca_trust_bundle
  tags                                 = var.tags
}
