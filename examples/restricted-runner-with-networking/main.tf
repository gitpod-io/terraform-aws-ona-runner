provider "aws" {
  region = var.aws_region
}

module "runner" {
  source = "../../modules/restricted-runner"

  pre_created_iam_roles             = var.pre_created_iam_roles
  environment_instance_profile_name = var.environment_instance_profile_name

  runner_id         = var.runner_id
  runner_token      = var.runner_token
  api_endpoint      = var.api_endpoint
  runner_name       = var.runner_name
  vpc_id            = aws_vpc.this.id
  runner_subnet_ids = [for zone in var.availability_zones : aws_subnet.runner[zone].id]

  proxy_config           = var.proxy_config
  custom_ca_trust_bundle = var.custom_ca_trust_bundle
}
