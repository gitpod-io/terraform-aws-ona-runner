provider "aws" {
  region = var.aws_region
}

module "runner" {
  source = "../../modules/restricted-runner"

  runner_id               = var.runner_id
  runner_token            = var.runner_token
  runner_name             = var.runner_name
  vpc_id                  = aws_vpc.this.id
  runner_subnet_ids       = [for zone in var.availability_zones : aws_subnet.runner[zone].id]
  internal_llm_proxy_port = var.internal_llm_proxy_port
  tags                    = var.tags
}
