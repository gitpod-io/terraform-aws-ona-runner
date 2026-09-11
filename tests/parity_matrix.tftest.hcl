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

override_resource {
  target          = aws_security_group.external_credentials
  override_during = plan
  values          = { id = "sg-00000000000000003" }
}

run "external_credentials_default_off" {
  command = plan
  assert {
    condition     = length(aws_ecs_service.external_credentials) == 0 && length(aws_secretsmanager_secret.external_credential_issuer) == 0 && length(aws_vpc_security_group_ingress_rule.external_credential_lookup) == 0
    error_message = "The credential service, issuer and private lookup ingress must be absent by default."
  }
}

run "external_credentials_private_discovery" {
  command = plan
  variables { enable_external_credential_proxy = true }
  assert {
    condition     = length(aws_service_discovery_private_dns_namespace.internal_runner) == 1 && length(aws_service_discovery_service.external_credentials) == 1 && length(aws_ecs_service.external_credentials) == 1 && length(aws_lb.proxy) == 1
    error_message = "The proxy needs VM-accessible private discovery without an additional load balancer."
  }
  assert {
    condition     = aws_security_group_rule.ecs_from_load_balancer[0].to_port == 7071 && aws_security_group_rule.ecs_from_load_balancer_upper[0].from_port == 7073
    error_message = "The existing load balancer ingress range must exclude the private binding port."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.external_credential_lookup[0].referenced_security_group_id == aws_security_group.external_credentials[0].id && aws_vpc_security_group_ingress_rule.external_credential_lookup[0].from_port == 7072 && aws_vpc_security_group_ingress_rule.external_credential_data[0].referenced_security_group_id == aws_security_group.environment.id && aws_vpc_security_group_ingress_rule.external_credential_data[0].from_port == 8443
    error_message = "Only the dedicated proxy group may use the binding lookup; Environment access is restricted to the data listener."
  }
}

run "external_credentials_reserve_lookup_port" {
  command = plan
  variables {
    enable_external_credential_proxy = true
    restrict_ingress                 = true
    internal_llm_proxy_port          = 7072
  }
  expect_failures = [aws_ecs_task_definition.external_credentials]
}

run "external_credentials_with_restricted_ingress" {
  command = plan
  variables {
    enable_external_credential_proxy = true
    restrict_ingress                 = true
  }
  assert {
    condition     = length(aws_lb.proxy) == 0 && length(aws_ecs_service.proxy) == 0 && length(aws_ecs_service.external_credentials) == 1 && length(aws_service_discovery_private_dns_namespace.internal_runner) == 1 && length(aws_ecs_service.runner.service_registries) == 1
    error_message = "Restricted ingress must retain the credential proxy and reuse the existing private runner registration."
  }
}

override_resource {
  target          = aws_security_group.ecs
  override_during = plan
  values = {
    id = "sg-00000000000000001"
  }
}

override_resource {
  target          = aws_security_group.environment
  override_during = plan
  values = {
    id = "sg-00000000000000002"
  }
}

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
    condition     = !var.restrict_ingress && one(aws_lb.proxy).internal && length(aws_memorydb_cluster.this) == 1 && length(aws_elasticache_cluster.this) == 0 && local.private_ecr_prefix == "025066274397.dkr.ecr.us-east-1.amazonaws.com/gitpod/ecr"
    error_message = "the default deployment must be a standard runner using an internal Network Load Balancer, MemoryDB, and the released private ECR mirror."
  }

  assert {
    condition     = aws_ssm_parameter.redis_connection.type == "SecureString"
    error_message = "the cache connection string must remain encrypted in Parameter Store."
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
    condition     = one(aws_lb.proxy).dns_record_client_routing_policy == "availability_zone_affinity" && one(aws_lb_target_group.proxy).health_check[0].matcher == "200"
    error_message = "the Network Load Balancer must retain the CloudFormation routing and health-check contract."
  }

  assert {
    condition     = one(aws_security_group.environment.ingress).from_port == 1024 && one(aws_security_group.environment.ingress).to_port == 65535
    error_message = "omitting restrict_ingress must preserve the standard environment ingress range."
  }

  assert {
    condition = (
      length(aws_lb.proxy) == 1 &&
      length(aws_lb_target_group.proxy) == 1 &&
      length(aws_lb_listener.proxy_tls) == 1 &&
      length(aws_cloudwatch_log_group.proxy) == 1 &&
      length(aws_ecs_task_definition.proxy) == 1 &&
      length(aws_ecs_service.proxy) == 1 &&
      length(aws_appautoscaling_target.proxy) == 1 &&
      length(aws_appautoscaling_policy.proxy_cpu) == 1 &&
      length(aws_appautoscaling_policy.proxy_memory) == 1 &&
      length(aws_iam_role.proxy) == 1 &&
      length(aws_iam_role_policy.proxy) == 1 &&
      length(aws_iam_policy.proxy_boundary) == 1 &&
      length(aws_security_group.load_balancer) == 1 &&
      length(aws_security_group_rule.ecs_from_load_balancer) == 1 &&
      length(aws_security_group_rule.ecs_portspec_self) == 1 &&
      length(aws_security_group_rule.ecs_runner_api_self) == 1 &&
      length(aws_security_group_rule.ecs_proxy_metrics_self) == 1
    )
    error_message = "omitting restrict_ingress must preserve all standard load balancer and proxy resources."
  }

  assert {
    condition = (
      length(aws_service_discovery_private_dns_namespace.internal_runner) == 0 &&
      length(aws_service_discovery_service.internal_runner) == 0 &&
      length(aws_secretsmanager_secret.internal_llm_tls) == 0 &&
      length(aws_security_group_rule.ecs_from_environment_llm) == 0 &&
      length(aws_ecs_service.runner.service_registries) == 0 &&
      length([for mapping in local.runner_container.portMappings : mapping if mapping.name == "llm-proxy"]) == 0 &&
      length(local.internal_runner_config_fragments) == 0
    )
    error_message = "omitting restrict_ingress must not create or configure the internal LLM route."
  }
}

run "explicit_unrestricted_ingress_preserves_default_topology" {
  command = plan

  variables {
    restrict_ingress = false
  }

  assert {
    condition     = !var.restrict_ingress && one(aws_lb.proxy).internal && aws_ecs_service.runner.desired_count == 1 && one(aws_ecs_service.proxy).desired_count == 2 && aws_ecs_service.adot.desired_count == 1
    error_message = "explicitly disabling restrict_ingress must preserve the standard runner topology."
  }

  assert {
    condition     = one(aws_security_group.environment.ingress).from_port == 1024 && one(aws_security_group.environment.ingress).to_port == 65535
    error_message = "explicitly disabling restrict_ingress must preserve the standard environment ingress range."
  }
}

run "restricted_ingress_limits_environment_access_to_supervisor" {
  command = plan

  variables {
    restrict_ingress                = true
    runner_domain                   = null
    certificate_arn                 = null
    load_balancer_subnet_ids        = []
    load_balancer_security_group_id = "sg-caller-supplied-but-unused"
  }

  assert {
    condition     = var.restrict_ingress && one(aws_security_group.environment.ingress).protocol == "tcp" && one(aws_security_group.environment.ingress).from_port == 22999 && one(aws_security_group.environment.ingress).to_port == 22999
    error_message = "enabling restrict_ingress must allow runner-to-environment TCP traffic only on supervisor control port 22999."
  }

  assert {
    condition = (
      length(aws_lb.proxy) == 0 &&
      length(aws_lb_target_group.proxy) == 0 &&
      length(aws_lb_listener.proxy_tls) == 0 &&
      length(aws_cloudwatch_log_group.proxy) == 0 &&
      length(aws_ecs_task_definition.proxy) == 0 &&
      length(aws_ecs_service.proxy) == 0 &&
      length(aws_appautoscaling_target.proxy) == 0 &&
      length(aws_appautoscaling_policy.proxy_cpu) == 0 &&
      length(aws_appautoscaling_policy.proxy_memory) == 0 &&
      length(aws_iam_role.proxy) == 0 &&
      length(aws_iam_role_policy.proxy) == 0 &&
      length(aws_iam_policy.proxy_boundary) == 0
    )
    error_message = "restricted ingress must omit the load balancer and proxy ECS, autoscaling, and IAM resources."
  }

  assert {
    condition = (
      coalesce(output.load_balancer_dns_name, "absent") == "absent" &&
      coalesce(output.load_balancer_arn, "absent") == "absent" &&
      coalesce(output.load_balancer_zone_id, "absent") == "absent" &&
      coalesce(output.load_balancer_security_group_id, "absent") == "absent" &&
      coalesce(output.proxy_ecs_service_name, "absent") == "absent"
    )
    error_message = "restricted ingress must report null for omitted load balancer and proxy outputs."
  }

  assert {
    condition = (
      length(aws_security_group.load_balancer) == 0 &&
      length(aws_security_group_rule.ecs_from_load_balancer) == 0 &&
      length(aws_security_group_rule.ecs_portspec_self) == 0 &&
      length(aws_security_group_rule.ecs_runner_api_self) == 0 &&
      length(aws_security_group_rule.ecs_proxy_metrics_self) == 0 &&
      length([for mapping in local.runner_container.portMappings : mapping if contains(["runner-api", "portspec"], mapping.name)]) == 0 &&
      length(aws_ecs_service.runner.service_connect_configuration[0].service) == 0
    )
    error_message = "restricted ingress must omit proxy-only security group rules, ports, and Service Connect registrations."
  }

  assert {
    condition = (
      length(local.proxy_log_config_fragments) == 0 &&
      local.runner_proxy_domain_config_fragments == [",\"runnerProxyDomain\":", "\"\""] &&
      local.ssh_over_gateway == "false"
    )
    error_message = "restricted ingress must omit external endpoint configuration."
  }

  assert {
    condition     = output.ssh_port == 29222
    error_message = "restricting supervisor ingress must not change the separate SSH port setting."
  }

  assert {
    condition = (
      length(aws_service_discovery_private_dns_namespace.internal_runner) == 1 &&
      one(aws_service_discovery_private_dns_namespace.internal_runner).name == local.internal_runner_namespace &&
      one(aws_service_discovery_private_dns_namespace.internal_runner).vpc == var.vpc_id &&
      length(aws_service_discovery_service.internal_runner) == 1 &&
      one(aws_service_discovery_service.internal_runner).name == "runner" &&
      one(one(aws_service_discovery_service.internal_runner).dns_config).routing_policy == "MULTIVALUE" &&
      one(one(one(aws_service_discovery_service.internal_runner).dns_config).dns_records).type == "A" &&
      one(one(one(aws_service_discovery_service.internal_runner).dns_config).dns_records).ttl == 10 &&
      one(aws_ecs_service.runner.service_registries).registry_arn == one(aws_service_discovery_service.internal_runner).arn
    )
    error_message = "restricted ingress must register rotating runner tasks in a private Cloud Map A-record service."
  }

  assert {
    condition = (
      length(aws_security_group_rule.ecs_from_environment_llm) == 1 &&
      one(aws_security_group_rule.ecs_from_environment_llm).security_group_id == aws_security_group.ecs.id &&
      one(aws_security_group_rule.ecs_from_environment_llm).source_security_group_id == aws_security_group.environment.id &&
      one(aws_security_group_rule.ecs_from_environment_llm).from_port == var.internal_llm_proxy_port &&
      one(aws_security_group_rule.ecs_from_environment_llm).to_port == var.internal_llm_proxy_port &&
      one([for mapping in local.runner_container.portMappings : mapping if mapping.name == "llm-proxy"]).containerPort == var.internal_llm_proxy_port
    )
    error_message = "restricted ingress must allow environments to reach only the runner's configured LLM listener port."
  }

  assert {
    condition = (
      length(aws_secretsmanager_secret.internal_llm_tls) == 1 &&
      length(local.internal_runner_config_fragments) == 6 &&
      local.internal_runner_config_fragments[0] == ",\"internalRunnerEndpoint\":" &&
      local.internal_runner_config_fragments[1] == jsonencode(local.internal_runner_endpoint) &&
      local.internal_runner_config_fragments[2] == ",\"internalRunnerLLMPort\":" &&
      local.internal_runner_config_fragments[3] == jsonencode(var.internal_llm_proxy_port) &&
      local.internal_runner_config_fragments[4] == ",\"internalRunnerTLSSecretARN\":" &&
      local.internal_runner_config_fragments[5] == jsonencode(one(aws_secretsmanager_secret.internal_llm_tls).arn)
    )
    error_message = "restricted ingress must configure the HTTPS endpoint and provision its TLS secret."
  }
}

run "restricted_ingress_keeps_custom_llm_port_in_sync" {
  command = plan

  variables {
    restrict_ingress        = true
    internal_llm_proxy_port = 9443
  }

  assert {
    condition = (
      local.internal_runner_endpoint == "https://runner.${local.internal_runner_namespace}:9443" &&
      one(aws_security_group_rule.ecs_from_environment_llm).from_port == 9443 &&
      one(aws_security_group_rule.ecs_from_environment_llm).to_port == 9443 &&
      one([for mapping in local.runner_container.portMappings : mapping if mapping.name == "llm-proxy"]).containerPort == 9443 &&
      local.internal_runner_config_fragments[3] == "9443"
    )
    error_message = "a custom internal LLM port must update the URL, task definition, security group, and runner configuration together."
  }
}

run "internal_llm_proxy_port_rejects_runner_port_conflicts" {
  command = plan

  variables {
    restrict_ingress        = true
    internal_llm_proxy_port = 8081
  }

  expect_failures = [var.internal_llm_proxy_port]
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
    condition     = !one(aws_lb.proxy).internal && length(aws_memorydb_cluster.this) == 0 && length(aws_elasticache_cluster.this) == 1
    error_message = "the public ElastiCache option must create only the supported ElastiCache branch."
  }

  assert {
    condition     = aws_ecs_task_definition.runner.cpu == "4096" && aws_ecs_task_definition.runner.memory == "16384" && aws_ecs_service.runner.desired_count == 2
    error_message = "large runners must use the CloudFormation Fargate runner sizing and replica count."
  }

  assert {
    condition     = one(aws_ecs_task_definition.proxy).cpu == "2048" && one(aws_ecs_task_definition.proxy).memory == "4096" && aws_appautoscaling_target.runner.min_capacity == 2 && aws_appautoscaling_target.runner.max_capacity == 16 && one(aws_appautoscaling_target.proxy).min_capacity == 2 && one(aws_appautoscaling_target.proxy).max_capacity == 16
    error_message = "large runners must scale the proxy and runner autoscaling bounds together."
  }

  assert {
    condition     = aws_ecs_service.runner.network_configuration[0].assign_public_ip && one(aws_ecs_service.proxy).network_configuration[0].assign_public_ip && aws_ecs_service.adot.network_configuration[0].assign_public_ip
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
    condition     = one(aws_ecs_service.proxy).health_check_grace_period_seconds == 60 && aws_ecs_service.runner.wait_for_steady_state && one(aws_ecs_service.proxy).wait_for_steady_state && aws_ecs_service.adot.wait_for_steady_state
    error_message = "ECS services must wait for steady state and preserve the proxy load-balancer health grace period."
  }

  assert {
    condition     = toset(aws_ecs_cluster_capacity_providers.this.capacity_providers) == toset(["FARGATE", "FARGATE_SPOT"])
    error_message = "the ECS cluster must register the CloudFormation Fargate capacity providers."
  }

  assert {
    condition     = aws_ecs_service.runner.service_connect_configuration[0].log_configuration[0].options["awslogs-stream-prefix"] == "service-connect-runner" && one(aws_ecs_service.proxy).service_connect_configuration[0].log_configuration[0].options["awslogs-stream-prefix"] == "service-connect-proxy"
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
