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
}

mock_provider "random" {}

variables {
  runner_id                = "019d6999-807b-7e52-ab6f-c9202f13ecf2"
  runner_token             = "test-token"
  runner_domain            = "runner.example.com"
  certificate_arn          = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  vpc_id                   = "vpc-00000000000000000"
  runner_subnet_ids        = ["subnet-00000000000000000"]
  load_balancer_subnet_ids = ["subnet-00000000000000000"]
}

run "internal_memorydb_small_matches_cloudformation_defaults" {
  command = plan

  assert {
    condition     = aws_lb.proxy.internal && length(aws_memorydb_cluster.this) == 1 && length(aws_elasticache_cluster.this) == 0 && local.private_ecr_prefix == "025066274397.dkr.ecr.us-east-1.amazonaws.com/gitpod/ecr"
    error_message = "the default deployment must use an internal Network Load Balancer, MemoryDB, and the released private ECR mirror."
  }

  assert {
    condition     = local.runner_container.image == "025066274397.dkr.ecr.us-east-1.amazonaws.com/gitpod/ecr/k5t9d3j5/application/gitpod-next/gitpod-ec2-runner:${var.runner_template_build_version}" && local.proxy_container.image == "025066274397.dkr.ecr.us-east-1.amazonaws.com/gitpod/ecr/k5t9d3j5/application/gitpod-next/gitpod-proxy:${var.runner_template_build_version}"
    error_message = "public manifest images must map to the regional private ECR release mirror."
  }

  assert {
    condition     = aws_ecs_task_definition.runner.cpu == "1024" && aws_ecs_task_definition.runner.memory == "3072" && aws_ecs_service.runner.desired_count == 1
    error_message = "small runners must use the CloudFormation Fargate runner sizing."
  }

  assert {
    condition     = aws_appautoscaling_target.runner.min_capacity == 1 && aws_appautoscaling_target.runner.max_capacity == 8 && output.ssh_port == 29222
    error_message = "small runners must retain their supported autoscaling and SSH output contract."
  }

  assert {
    condition     = aws_lb.proxy.dns_record_client_routing_policy == "availability_zone_affinity" && aws_lb_target_group.proxy.health_check[0].matcher == "200"
    error_message = "the Network Load Balancer must retain the CloudFormation routing and health-check contract."
  }
}

run "public_elasticache_large_matches_cloudformation_options" {
  command = plan

  variables {
    load_balancer_scheme = "internet-facing"
    assign_public_ip     = true
    cache_engine         = "ElastiCache"
    runner_size          = "large"
  }

  assert {
    condition     = !aws_lb.proxy.internal && length(aws_memorydb_cluster.this) == 0 && length(aws_elasticache_cluster.this) == 1
    error_message = "the public ElastiCache option must create only the supported ElastiCache branch."
  }

  assert {
    condition     = aws_ecs_task_definition.runner.cpu == "4096" && aws_ecs_task_definition.runner.memory == "16384" && aws_ecs_service.runner.desired_count == 2
    error_message = "large runners must use the CloudFormation Fargate runner sizing and replica count."
  }

  assert {
    condition     = aws_ecs_task_definition.proxy.cpu == "2048" && aws_ecs_task_definition.proxy.memory == "4096" && aws_appautoscaling_target.runner.min_capacity == 2 && aws_appautoscaling_target.runner.max_capacity == 16 && aws_appautoscaling_target.proxy.min_capacity == 2 && aws_appautoscaling_target.proxy.max_capacity == 16
    error_message = "large runners must scale the proxy and runner autoscaling bounds together."
  }

  assert {
    condition     = aws_ecs_service.runner.network_configuration[0].assign_public_ip && aws_ecs_service.proxy.network_configuration[0].assign_public_ip && aws_ecs_service.adot.network_configuration[0].assign_public_ip
    error_message = "AssignPublicIp must apply to all supported Fargate services."
  }
}

run "proxy_and_custom_ca_configuration_reaches_task_contract" {
  command = plan

  variables {
    proxy_config = {
      http_proxy  = "http://proxy.example.com:3128"
      https_proxy = "https://proxy.example.com:3129"
      all_proxy   = "socks5://proxy.example.com:1080"
      no_proxy    = "localhost,runner.example.com"
    }
    custom_ca_trust_bundle = "https://example.com/runner-ca.pem"
  }

  assert {
    condition     = tolist(local.proxy_env) == tolist(["http_proxy=http://proxy.example.com:3128", "https_proxy=https://proxy.example.com:3129", "all_proxy=socks5://proxy.example.com:1080", "no_proxy=localhost,runner.example.com"])
    error_message = "the CloudFormation proxy inputs must retain their values in the shared task environment contract."
  }

  assert {
    condition     = one([for item in local.ca_init_container.environment : item if item.name == "GITPOD_CUSTOM_CA_BUNDLE"]).value == "https://example.com/runner-ca.pem"
    error_message = "the custom CA input must be passed to the runner CA initialization container."
  }
}

run "runner_configuration_matches_cloudformation_fixed_contract" {
  command = plan

  assert {
    condition     = length([for item in local.runner_container.environment : item if item.name == "GITPOD_DEVELOPMENT_VERSION"]) == 0
    error_message = "the runner task must not expose a Terraform-only development-version override."
  }
}

run "runtime_services_match_cloudformation_lifecycle" {
  command = plan

  assert {
    condition     = aws_ecs_service.proxy.health_check_grace_period_seconds == 60 && aws_ecs_service.runner.wait_for_steady_state && aws_ecs_service.proxy.wait_for_steady_state && aws_ecs_service.adot.wait_for_steady_state
    error_message = "ECS services must wait for steady state and preserve the proxy load-balancer health grace period."
  }

  assert {
    condition     = toset(aws_ecs_cluster_capacity_providers.this.capacity_providers) == toset(["FARGATE", "FARGATE_SPOT"])
    error_message = "the ECS cluster must register the CloudFormation Fargate capacity providers."
  }

  assert {
    condition     = aws_ecs_service.runner.service_connect_configuration[0].log_configuration[0].options["awslogs-stream-prefix"] == "service-connect-runner" && aws_ecs_service.proxy.service_connect_configuration[0].log_configuration[0].options["awslogs-stream-prefix"] == "service-connect-proxy"
    error_message = "runner and proxy Service Connect traffic must use the CloudFormation log streams."
  }

  assert {
    condition     = local.runner_container.stopTimeout == 120 && local.proxy_container.stopTimeout == 120
    error_message = "runner and proxy containers must retain the CloudFormation shutdown timeout."
  }

  assert {
    condition     = contains(local.ecs_runtime_discovery_actions, "ecs:DescribeClusters") && contains(local.ecs_runtime_discovery_actions, "ecs:ListServices")
    error_message = "the runner role must be able to discover the proxy and ADOT services."
  }

  assert {
    condition = alltrue([
      for policy in [
        local.ecs_execution_boundary_policy,
        local.ecs_task_boundary_policy,
        local.proxy_boundary_policy,
        local.adot_boundary_policy,
        local.environment_boundary_policy,
        local.s3_access_boundary_policy,
        local.devcontainer_cache_boundary_policy,
      ] : length(jsonencode(policy)) <= 6144
    ])
    error_message = "each generated permission boundary must fit the AWS managed-policy size limit."
  }
}

run "private_ecr_release_image_derives_runner_update_prefix" {
  command = plan

  variables {
    runner_template_build_version = "test-release"
    runner_image                  = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr/application/gitpod-next/gitpod-ec2-runner:test-release"
    proxy_image                   = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr/application/gitpod-next/gitpod-proxy:test-release"
  }

  assert {
    condition     = local.private_ecr_prefix == "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr"
    error_message = "private-ECR runner images must preserve the CloudFormation update prefix."
  }

  assert {
    condition     = local.adot_container.image == "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr/k5t9d3j5/application/gitpod-next/external/aws-otel-collector:v0.43.3" && local.metrics_audit_sync_container.image == "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr/k5t9d3j5/application/gitpod-next/external/aws-cli:2.27.22@sha256:1d5753647df57828762601f4d82790f3441060dbc8671cd01c52df05cfd3b2c7"
    error_message = "private-ECR sidecar images must be derived from the same CloudFormation private ECR prefix."
  }
}

run "private_ecr_release_image_rejects_mixed_image_sources" {
  command = plan

  variables {
    runner_template_build_version = "test-release"
    runner_image                  = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr/application/gitpod-next/gitpod-ec2-runner:test-release"
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "public_runner_image_rejects_private_proxy_image" {
  command = plan

  variables {
    runner_template_build_version = "test-release"
    runner_image                  = "public.ecr.aws/example/custom-runner:test-release"
    proxy_image                   = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr/example/custom-proxy:test-release"
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "private_runner_image_rejects_public_proxy_image" {
  command = plan

  variables {
    runner_template_build_version = "test-release"
    runner_image                  = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/gitpod/ecr/example/custom-runner:test-release"
    proxy_image                   = "public.ecr.aws/example/custom-proxy:test-release"
  }

  expect_failures = [aws_ecs_cluster.this]
}
