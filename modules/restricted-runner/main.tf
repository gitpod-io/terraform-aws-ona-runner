module "runner" {
  source = "../.."

  runner_id                              = var.runner_id
  runner_token                           = var.runner_token
  runner_name                            = var.runner_name
  vpc_id                                 = var.vpc_id
  runner_subnet_ids                      = var.runner_subnet_ids
  restrict_ingress                       = true
  external_credential_proxy_ers_upstream = var.external_credential_proxy_ers_upstream
}
