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

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-runner-role"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      name = "test-environment-profile"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-00000000000000001"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      bucket = "gitpod-test-bucket"
    }
  }

  mock_resource "aws_ssm_parameter" {
    defaults = {
      arn = "arn:aws:ssm:us-east-1:123456789012:parameter/test-config"
    }
  }
}

mock_provider "random" {}
mock_provider "http" {}
mock_provider "archive" {}

variables {
  runner_id         = "runner-a"
  runner_token      = "test-token"
  vpc_id            = "vpc-00000000000000000"
  runner_subnet_ids = ["subnet-00000000000000000"]
}

run "restricted_runner_plans_without_ingress_inputs" {
  command = plan

  assert {
    condition     = output.runner_config_parameter_name == "/gitpod/runner/runner-a"
    error_message = "the wrapper must forward runner configuration outputs from the restricted child module."
  }

  assert {
    condition     = output.release_version == "20260917.975" && output.ssh_port == 29222
    error_message = "the wrapper must preserve the current production release default and SSH output contract when the version input is omitted."
  }

  assert {
    condition     = output.ecs_cluster_name == "ona-runner-51cf5b27370ded93-ona-cluster"
    error_message = "the wrapper must preserve the root module runner_name default."
  }
}

run "custom_runner_name_is_forwarded" {
  command = plan

  variables {
    runner_name = "defense"
  }

  assert {
    condition     = output.ecs_cluster_name == "defense-51cf5b27370ded93-ona-cluster"
    error_message = "the wrapper must forward runner_name to the root module."
  }
}

# Rendered child task definitions are checked by test-restricted-runner-settings.sh.
run "ca_proxy_defaults" {
  command = plan
}

run "ca_proxy_custom" {
  command = plan

  variables {
    proxy_config = {
      http_proxy  = "http://proxy.example.com:3128"
      https_proxy = "http://proxy.example.com:3129"
      all_proxy   = "socks5://proxy.example.com:1080"
      no_proxy    = "localhost,127.0.0.1,.internal,.amazonaws.com,169.254.0.0/16,app.gitpod.io,.corp.example"
    }
    custom_ca_trust_bundle = "s3://gitpod-example/shared/ca-bundle.pem"
  }
}

run "ca_proxy_partial" {
  command = plan

  variables {
    proxy_config = {
      https_proxy = "http://proxy.example.com:3128"
    }
  }
}

run "api_endpoint_default" {
  command = plan
}

run "api_endpoint_custom" {
  command = plan

  variables {
    api_endpoint = "https://ona.example.com/api"
  }
}

run "prepare_forwards_validated_control_inputs" {
  command = plan

  variables {
    runner_iam_phase              = "prepare"
    runner_releases_url           = "https://releases.example.com"
    runner_template_build_version = "20260917.657"
    custom_ca_trust_bundle        = "s3://gitpod-customer-ca/shared/ca-bundle.pem"
    custom_ca_s3_object_arn       = "arn:aws:s3:::gitpod-customer-ca/shared/ca-bundle.pem"
  }

  override_data {
    target = module.runner.data.http.runner_release_manifest
    values = {
      response_body = <<-JSON
        {"version":"20260917.657","image_digest":"public.ecr.aws/example/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","proxy_image_digest":"public.ecr.aws/example/proxy@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runner_control_protocol":1,"runner_control_source_sha256":"sha256:61e3e54dc5206a73859ff79d1e723648214b0d6510f96b3c665f561aca60c2d6","cloudformation_template_url":"https://releases.example.com/ec2/releases/20260917.657/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"}
      JSON
    }
  }

  override_data {
    target = module.runner.data.http.runner_release_template
    values = {
      response_body = <<-JSON
        {"Resources":{"Control":{"Type":"AWS::Lambda::Function","Properties":{"Handler":"index.handler","Code":{"ZipFile":"exports.handler = async () => ({ ok: true });"},"Environment":{"Variables":{"APPROVED_IMAGE_IDS":"ami-00000000000000001"}}}}}}
      JSON
    }
  }

  override_data {
    target = module.runner.data.archive_file.runner_control
    values = {
      output_path         = "/tmp/restricted-runner-control.zip"
      output_base64sha256 = "YWJj"
    }
  }

  assert {
    condition     = output.runner_iam_phase == "prepare" && output.release_version == "20260917.657"
    error_message = "the restricted wrapper must forward the explicit fixture phase and version while retaining its proxy-free topology."
  }
}
