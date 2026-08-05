provider "aws" {
  region = var.aws_region
}

module "runner" {
  source = "../.."

  runner_id                     = var.runner_id
  runner_token                  = var.runner_token
  runner_image                  = var.runner_image
  proxy_image                   = var.proxy_image
  private_ecr_prefix            = var.private_ecr_prefix
  runner_template_build_version = var.runner_template_build_version
  runner_name                   = "ona-runner"
  runner_domain                 = var.runner_domain
  certificate_arn               = var.certificate_arn
  vpc_id                        = var.vpc_id
  runner_subnet_ids             = var.runner_subnet_ids
  load_balancer_subnet_ids      = var.load_balancer_subnet_ids

  load_balancer_scheme = "internal"
}
