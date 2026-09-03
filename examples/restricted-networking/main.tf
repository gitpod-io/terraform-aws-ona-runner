provider "aws" {
  region = var.aws_region
}

module "restricted_networking" {
  source = "../../modules/restricted-networking"

  name                  = var.network_name
  availability_zones    = var.availability_zones
  routable_vpc_cidr     = var.routable_vpc_cidr
  runner_cgnat_cidr     = var.runner_cgnat_cidr
  enable_firewall       = var.enable_firewall
  egress                = var.egress
  firewall_policy_arn   = var.firewall_policy_arn
  log_retention_in_days = var.log_retention_in_days
  log_kms_key_arn       = var.log_kms_key_arn
  tags                  = var.tags
}
