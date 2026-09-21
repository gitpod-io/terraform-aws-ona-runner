terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60.0"
    }
  }
}

module "runner" {
  source = "../../../examples/restricted-runner-with-networking"

  aws_region         = "us-east-1"
  availability_zones = ["us-east-1a", "us-east-1b"]
  routable_vpc_cidr  = "10.0.0.0/16"
  runner_id          = "00000000-0000-4000-8000-000000000001"
  runner_token       = "synthetic-test-token"
}
