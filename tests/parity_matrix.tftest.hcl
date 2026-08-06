mock_provider "aws" {
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
  runner_id                     = "019d6999-807b-7e52-ab6f-c9202f13ecf2"
  runner_token                  = "test-token"
  runner_image                  = "public.ecr.aws/ona/gitpod-ec2-runner:v2026.08.0"
  proxy_image                   = "public.ecr.aws/ona/gitpod-proxy:v2026.08.0"
  runner_template_build_version = "v2026.08.0"
  runner_domain                 = "runner.example.com"
  certificate_arn               = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  vpc_id                        = "vpc-00000000000000000"
  runner_subnet_ids             = ["subnet-00000000000000000"]
  load_balancer_subnet_ids      = ["subnet-00000000000000000"]
}

run "internal_memorydb_small_matches_cloudformation_defaults" {
  command = plan

  assert {
    condition     = aws_lb.proxy.internal && length(aws_memorydb_cluster.this) == 1 && length(aws_elasticache_cluster.this) == 0
    error_message = "the default deployment must use an internal Network Load Balancer and MemoryDB."
  }

  assert {
    condition     = aws_ecs_task_definition.runner.cpu == "1024" && aws_ecs_task_definition.runner.memory == "3072" && aws_ecs_service.runner.desired_count == 1
    error_message = "small runners must use the CloudFormation Fargate runner sizing."
  }

  assert {
    condition     = aws_appautoscaling_target.runner.min_capacity == 1 && aws_appautoscaling_target.runner.max_capacity == 8 && output.ssh_port == 29222
    error_message = "small runners must retain their supported autoscaling and SSH output contract."
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
