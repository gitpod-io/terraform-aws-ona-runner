provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variable "routable_vpc_cidr" {
  default = "10.42.0.0/24"
}

variable "runner_cgnat_cidr" {
  default = "100.64.0.0/16"
}

variable "runner_domains" {
  type    = list(string)
  default = ["example.com"]
}

variable "environment_domains" {
  type    = list(string)
  default = ["example.com"]
}

locals {
  network_name     = "test-migration"
  common_tags      = {}
  firewall_managed = true
  firewall_config = {
    runner_allowed_domains      = var.runner_domains
    environment_allowed_domains = var.environment_domains
  }
  firewall_config_domains  = { runner = var.runner_domains, environment = var.environment_domains }
  firewall_allowed_domains = local.firewall_config_domains
  firewall_rule_priorities = { runner = 100, environment = 200 }
  firewall_source_arns = {
    runner      = "arn:aws:network-firewall:us-east-1:123456789012:container-association/test-runner"
    environment = "arn:aws:resource-groups:us-east-1:123456789012:group/test-environments"
  }
}
