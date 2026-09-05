mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_resource "aws_service_discovery_service" {
    defaults = {
      arn = "arn:aws:servicediscovery:us-east-1:123456789012:service/srv-internal-runner"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:internal-runner-tls"
    }
  }
}

mock_provider "random" {}

variables {
  runner_id         = "019d6999-807b-7e52-ab6f-c9202f13ecf2"
  runner_token      = "test-token"
  vpc_id            = "vpc-00000000000000000"
  runner_subnet_ids = ["subnet-00000000000000000"]
}

run "restricted_runner_plans_without_ingress_inputs" {
  command = plan

  assert {
    condition     = output.runner_config_parameter_name == "/gitpod/runner/019d6999-807b-7e52-ab6f-c9202f13ecf2"
    error_message = "the wrapper must forward runner configuration outputs from the restricted child module."
  }

  assert {
    condition     = can(regex("^[0-9]{8}\\.[0-9]+$", output.release_version)) && output.ssh_port == 29222
    error_message = "the wrapper must inherit the root module release and SSH output contract."
  }
}
