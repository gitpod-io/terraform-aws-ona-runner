mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
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

  mock_data "aws_vpc_endpoint_service" {
    defaults = {
      availability_zones = ["us-east-1b", "us-east-1c"]
    }
  }

  mock_resource "aws_networkfirewall_firewall" {
    defaults = {
      arn = "arn:aws:network-firewall:us-east-1:123456789012:firewall/ona-runner-network"
      firewall_status = [{
        sync_states = [
          {
            availability_zone = "us-east-1a"
            attachment = [{
              endpoint_id = "vpce-00000000000000001"
              subnet_id   = "subnet-00000000000000001"
            }]
          },
          {
            availability_zone = "us-east-1b"
            attachment = [{
              endpoint_id = "vpce-00000000000000002"
              subnet_id   = "subnet-00000000000000002"
            }]
          },
          {
            availability_zone = "us-east-1c"
            attachment = [{
              endpoint_id = "vpce-00000000000000003"
              subnet_id   = "subnet-00000000000000003"
            }]
          },
        ]
      }]
    }
  }

  mock_resource "aws_vpc" {
    defaults = {
      id = "vpc-00000000000000001"
    }
  }

  mock_resource "aws_networkfirewall_rule_group" {
    defaults = {
      arn = "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/test-rule-group"
    }
  }

  mock_resource "aws_internet_gateway" {
    defaults = {
      id = "igw-00000000000000001"
    }
  }

  mock_resource "aws_nat_gateway" {
    defaults = {
      id = "nat-00000000000000001"
    }
  }

  mock_resource "aws_vpc_endpoint" {
    defaults = {
      # A sentinel distinguishes provider-default routing from an explicit service region.
      service_region = "provider-default"
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

  mock_resource "aws_subnet" {
    defaults = {
      id = "subnet-00000000000000001"
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

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:test-runner-secret"
    }
  }
}

mock_provider "random" {}

override_resource {
  target          = aws_security_group.vpc_endpoints
  override_during = plan
  values = {
    id = "sg-00000000000000001"
  }
}

variables {
  aws_region         = "us-east-1"
  runner_id          = "019d6999-807b-7e52-ab6f-c9202f13ecf2"
  runner_token       = "test-token"
  availability_zones = ["us-east-1a", "us-east-1b"]
  routable_vpc_cidr  = "10.42.0.0/24"
}

run "nat_gateway_mode_is_zonal_and_symmetric" {
  command = plan

  override_resource {
    target          = aws_networkfirewall_rule_group.control_manifest_reject[0]
    override_during = plan
    values = {
      arn = "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/control-manifest-reject"
    }
  }

  override_resource {
    target          = aws_networkfirewall_rule_group.allowed_domains[0]
    override_during = plan
    values = {
      arn = "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/allowed-domains"
    }
  }

  override_resource {
    target          = aws_subnet.runner["us-east-1a"]
    override_during = plan
    values = {
      id = "subnet-00000000000000001"
    }
  }

  override_resource {
    target          = aws_subnet.runner["us-east-1b"]
    override_during = plan
    values = {
      id = "subnet-00000000000000002"
    }
  }

  override_resource {
    target          = aws_route_table.runner["us-east-1a"]
    override_during = plan
    values = {
      id = "rtb-00000000000000001"
    }
  }

  override_resource {
    target          = aws_route_table.runner["us-east-1b"]
    override_during = plan
    values = {
      id = "rtb-00000000000000002"
    }
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.42.0.0/24" && aws_vpc_ipv4_cidr_block_association.runner.cidr_block == "100.64.0.0/16"
    error_message = "the VPC must use the routable range as primary and the CGNAT range as secondary."
  }

  assert {
    condition     = aws_networkfirewall_firewall.this[0].name == "ona-runner-2ec33d556332a866"
    error_message = "the default network name must derive from runner_name and the full runner ID."
  }

  assert {
    condition = (
      aws_networkfirewall_firewall_policy.default[0].description == "Default-deny policy for Ona runner egress inspection." &&
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_default_actions == toset(["aws:drop_established", "aws:alert_established"]) &&
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_engine_options[0].rule_order == "STRICT_ORDER" &&
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_engine_options[0].stream_exception_policy == "DROP" &&
      length(aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_rule_group_reference) == 2 &&
      length(aws_networkfirewall_rule_group.allowed_domains) == 1
    )
    error_message = "the default firewall policy must retain strict-order default denial and attach the baseline domain allowlist."
  }

  assert {
    condition = {
      for reference in aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_rule_group_reference :
      reference.priority => reference.resource_arn
      } == {
      "50"  = "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/control-manifest-reject"
      "100" = "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/allowed-domains"
    }
    error_message = "the manifest rejection must run before the allowlist's generated drop rule."
  }

  assert {
    condition = (
      aws_networkfirewall_rule_group.control_manifest_reject[0].type == "STATEFUL" &&
      aws_networkfirewall_rule_group.control_manifest_reject[0].capacity == 1 &&
      aws_networkfirewall_rule_group.control_manifest_reject[0].rule_group[0].stateful_rule_options[0].rule_order == "STRICT_ORDER" &&
      aws_networkfirewall_rule_group.control_manifest_reject[0].rule_group[0].rules_source[0].rules_string == "reject tls $HOME_NET any -> any 443 (ssl_state:client_hello; tls.sni; content:\"containers.dev\"; startswith; endswith; nocase; flow:to_server,established; msg:\"Reject devcontainer control manifest fetch\"; sid:1000001; rev:1;)"
    )
    error_message = "only established TLS requests to the exact containers.dev SNI on TCP/443 must be rejected, using a separate strict-order rule group."
  }

  assert {
    condition = (
      one(aws_networkfirewall_rule_group.control_manifest_reject[0].rule_group[0].rule_variables[0].ip_sets).key == "HOME_NET" &&
      toset(one(aws_networkfirewall_rule_group.control_manifest_reject[0].rule_group[0].rule_variables[0].ip_sets).ip_set[0].definition) == toset(["100.64.0.0/18", "100.64.64.0/18"])
    )
    error_message = "manifest rejection must be scoped to the runner subnets, not the routable VPC or reserved ranges."
  }

  assert {
    condition = aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets == toset([
      "api.linear.app",
      "github.com",
      "api.github.com",
      "codeload.github.com",
      ".githubusercontent.com",
      "api.atlassian.com",
      "api.openai.com",
      "mcr.microsoft.com",
      ".data.mcr.microsoft.com",
    ])
    error_message = "the default allowlist must contain exactly the reviewed integration, model API, and base-image endpoints, without broad provider wildcards."
  }

  assert {
    condition = toset(keys(aws_vpc_endpoint.aws_interface)) == toset([
      "acm",
      "cloudformation",
      "ec2",
      "ec2messages",
      "ecr.api",
      "ecr.dkr",
      "ecs",
      "ecs-agent",
      "ecs-telemetry",
      "elasticloadbalancing",
      "iam",
      "logs",
      "secretsmanager",
      "ssm",
      "ssmmessages",
      "sts",
    ])
    error_message = "the example must create every interface endpoint required by the public AWS runner networking documentation."
  }

  assert {
    condition = alltrue([
      for service, endpoint in aws_vpc_endpoint.aws_interface :
      endpoint.service_name == (service == "iam" ? "com.amazonaws.iam" : "com.amazonaws.us-east-1.${service}") &&
      endpoint.service_region == "provider-default" &&
      endpoint.vpc_endpoint_type == "Interface" &&
      endpoint.private_dns_enabled &&
      endpoint.subnet_ids == toset(["subnet-00000000000000001", "subnet-00000000000000002"]) &&
      endpoint.security_group_ids == toset([aws_security_group.vpc_endpoints.id])
    ])
    error_message = "AWS interface endpoints must use private DNS, every runner subnet, and the shared security group; IAM uses its global name without cross-region routing in us-east-1."
  }

  assert {
    condition = (
      toset(keys(aws_vpc_endpoint.aws_gateway)) == toset(["dynamodb", "s3"]) &&
      alltrue([
        for service, endpoint in aws_vpc_endpoint.aws_gateway :
        endpoint.service_name == "com.amazonaws.us-east-1.${service}" &&
        endpoint.vpc_endpoint_type == "Gateway" &&
        endpoint.route_table_ids == toset(["rtb-00000000000000001", "rtb-00000000000000002"])
      ])
    )
    error_message = "S3 and DynamoDB gateway endpoints must be associated with every runner route table."
  }

  assert {
    condition = (
      aws_vpc_endpoint.management_plane.service_name == "com.amazonaws.vpce.us-east-1.vpce-svc-08de744d433e60ff2" &&
      aws_vpc_endpoint.management_plane.private_dns_enabled &&
      aws_vpc_endpoint.management_plane.subnet_ids == toset(["subnet-00000000000000002"]) &&
      aws_vpc_endpoint.management_plane.security_group_ids == toset([aws_security_group.vpc_endpoints.id])
    )
    error_message = "the us-east-1 management-plane endpoint must enable private DNS and use the first configured runner subnet supported by the service without cross-region mode."
  }

  assert {
    condition = (
      toset(keys(aws_vpc_security_group_ingress_rule.vpc_endpoints_from_runner_subnets)) == toset(["us-east-1a", "us-east-1b"]) &&
      alltrue([
        for zone, rule in aws_vpc_security_group_ingress_rule.vpc_endpoints_from_runner_subnets :
        rule.cidr_ipv4 == local.runner_subnet_cidrs[zone] &&
        rule.cidr_ipv6 == null &&
        rule.referenced_security_group_id == null &&
        rule.ip_protocol == "tcp" &&
        rule.from_port == 443 &&
        rule.to_port == 443
      ])
    )
    error_message = "the endpoint security group must allow HTTPS only from each runner subnet CIDR."
  }

  assert {
    condition     = output.runner_subnet_cidrs == { "us-east-1a" = "100.64.0.0/18", "us-east-1b" = "100.64.64.0/18" } && output.runner_reserved_cidrs == ["100.64.128.0/17"]
    error_message = "two-AZ deployments must allocate the first CGNAT half and reserve the second half."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(aws_eip.nat) == 2 && length(aws_internet_gateway.this) == 1 && length(aws_ec2_transit_gateway_vpc_attachment.this) == 0 && length(aws_subnet.firewall) == 2
    error_message = "NAT mode must create one NAT Gateway and firewall subnet per availability zone and no Transit Gateway attachment."
  }

  assert {
    condition = (
      aws_route.runner_to_firewall["us-east-1a"].vpc_endpoint_id == "vpce-00000000000000001" &&
      aws_route.firewall_to_nat["us-east-1a"].nat_gateway_id == aws_nat_gateway.this["us-east-1a"].id &&
      aws_route.egress_to_internet_gateway["us-east-1a"].gateway_id == aws_internet_gateway.this[0].id &&
      length(aws_route.egress_to_runner) == 4 &&
      aws_route.egress_to_runner["us-east-1a:us-east-1a"].destination_cidr_block == "100.64.0.0/18" &&
      aws_route.egress_to_runner["us-east-1a:us-east-1b"].destination_cidr_block == "100.64.64.0/18" &&
      aws_route.egress_to_runner["us-east-1a:us-east-1b"].vpc_endpoint_id == "vpce-00000000000000001"
    )
    error_message = "NAT traffic and its return path must cross the same-zone firewall endpoint."
  }

  assert {
    condition     = aws_flow_log.vpc.traffic_type == "ALL" && aws_route53_resolver_query_log_config_association.this.resource_id == aws_vpc.this.id
    error_message = "VPC flow logging and VPC-level Resolver query logging must remain enabled."
  }

  assert {
    condition     = output.runner_config_parameter_name == "/gitpod/runner/019d6999-807b-7e52-ab6f-c9202f13ecf2"
    error_message = "the example must pass its VPC and runner subnets to the restricted runner module."
  }
}

run "explicit_network_name_overrides_the_derived_name" {
  command = plan

  variables {
    runner_name  = "defense"
    network_name = "existing-network"
  }

  assert {
    condition     = aws_networkfirewall_firewall.this[0].name == "existing-network"
    error_message = "an explicit network_name must override the runner-derived default."
  }
}

run "firewall_domain_allowlist_adds_to_baseline_and_normalizes_duplicates" {
  command = plan

  variables {
    firewall_allowed_domains = ["GitHub.com", "MCR.MICROSOFT.COM", "Packages.Example.com", "packages.example.com", ".corp.example"]
  }

  assert {
    condition = (
      length(aws_networkfirewall_rule_group.allowed_domains) == 1 &&
      aws_networkfirewall_rule_group.allowed_domains[0].capacity == 1000 &&
      aws_networkfirewall_rule_group.allowed_domains[0].type == "STATEFUL" &&
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].stateful_rule_options[0].rule_order == "STRICT_ORDER" &&
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].generated_rules_type == "ALLOWLIST" &&
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].target_types == toset(["TLS_SNI"]) &&
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets == toset([
        "api.linear.app",
        "github.com",
        "api.github.com",
        "codeload.github.com",
        ".githubusercontent.com",
        "api.atlassian.com",
        "api.openai.com",
        "mcr.microsoft.com",
        ".data.mcr.microsoft.com",
        "packages.example.com",
        ".corp.example",
      ])
    )
    error_message = "additional domains must extend, not replace, the TLS SNI baseline and must be deduplicated after lowercasing."
  }

  assert {
    condition = (
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_default_actions == toset(["aws:drop_established", "aws:alert_established"]) &&
      toset([for reference in aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_rule_group_reference : reference.priority]) == toset([50, 100])
    )
    error_message = "the default policy must attach the domain allowlist rule group."
  }
}

run "explicit_empty_allowlist_retains_baseline" {
  command = plan

  variables {
    firewall_allowed_domains = []
  }

  assert {
    condition = (
      length(aws_networkfirewall_rule_group.allowed_domains) == 1 &&
      length(aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets) == 9 &&
      contains(aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets, "api.openai.com") &&
      contains(aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets, ".data.mcr.microsoft.com")
    )
    error_message = "an explicitly empty additional allowlist must retain the baseline, including model access and base-image layers."
  }
}

run "combined_firewall_allowlist_accepts_capacity_boundary" {
  command = plan

  variables {
    firewall_allowed_domains = [for index in range(990) : "extra-${index}.example.com"]
  }

  assert {
    condition     = length(aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets) == 999
    error_message = "the baseline and additional domains must fit within the 1000-rule capacity, including the generated deny rule."
  }
}

run "combined_firewall_allowlist_rejects_capacity_overflow" {
  command = plan

  variables {
    firewall_allowed_domains = [for index in range(991) : "extra-${index}.example.com"]
  }

  expect_failures = [aws_networkfirewall_rule_group.allowed_domains[0]]
}

run "management_plane_requires_a_supported_same_region_zone" {
  command = plan

  override_data {
    target          = data.aws_vpc_endpoint_service.management_plane[0]
    override_during = plan
    values = {
      availability_zones = ["us-east-1c"]
    }
  }

  expect_failures = [aws_vpc_endpoint.management_plane]
}

run "custom_firewall_policy_replaces_the_managed_allowlist" {
  command = plan

  variables {
    firewall_policy_arn      = "arn:aws:network-firewall:us-east-1:123456789012:firewall-policy/customer-policy"
    firewall_allowed_domains = [for index in range(999) : "extra-${index}.example.com"]
  }

  assert {
    condition = (
      length(aws_networkfirewall_firewall_policy.default) == 0 &&
      length(aws_networkfirewall_rule_group.allowed_domains) == 0 &&
      length(aws_networkfirewall_rule_group.control_manifest_reject) == 0 &&
      aws_networkfirewall_firewall.this[0].firewall_policy_arn == "arn:aws:network-firewall:us-east-1:123456789012:firewall-policy/customer-policy"
    )
    error_message = "a custom firewall policy must replace both baseline and additional domains without enforcing the unused generated-rule capacity."
  }
}

run "iam_and_management_plane_use_cross_region_services_outside_us_east_1" {
  command = plan

  variables {
    aws_region         = "eu-central-1"
    availability_zones = ["eu-central-1a", "eu-central-1b"]
    enable_firewall    = false
  }

  override_resource {
    target          = aws_subnet.runner["eu-central-1a"]
    override_during = plan
    values = {
      id = "subnet-00000000000000001"
    }
  }

  override_resource {
    target          = aws_subnet.runner["eu-central-1b"]
    override_during = plan
    values = {
      id = "subnet-00000000000000002"
    }
  }

  assert {
    condition     = aws_vpc_endpoint.management_plane.service_region == "us-east-1"
    error_message = "deployments outside us-east-1 must use the cross-region Ona endpoint service."
  }

  assert {
    condition     = aws_vpc_endpoint.management_plane.subnet_ids == toset(["subnet-00000000000000001", "subnet-00000000000000002"])
    error_message = "cross-region management-plane endpoints must span every selected runner subnet."
  }

  assert {
    condition = alltrue([
      for service, endpoint in aws_vpc_endpoint.aws_interface :
      endpoint.service_name == (service == "iam" ? "com.amazonaws.iam" : "com.amazonaws.eu-central-1.${service}") &&
      endpoint.service_region == (service == "iam" ? "us-east-1" : "provider-default") &&
      endpoint.private_dns_enabled &&
      endpoint.subnet_ids == toset(["subnet-00000000000000001", "subnet-00000000000000002"]) &&
      endpoint.security_group_ids == toset([aws_security_group.vpc_endpoints.id])
    ])
    error_message = "IAM must use its global service in us-east-1 with private DNS and shared endpoint access; other AWS interface endpoints must remain regional."
  }
}

run "transit_gateway_mode_creates_an_appliance_attachment" {
  command = plan

  variables {
    egress = {
      mode               = "transit_gateway"
      transit_gateway_id = "tgw-0123456789abcdef0"
    }
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_internet_gateway.this) == 0 && length(aws_ec2_transit_gateway_vpc_attachment.this) == 1
    error_message = "Transit Gateway mode must not create public egress resources."
  }

  assert {
    condition = (
      aws_ec2_transit_gateway_vpc_attachment.this[0].appliance_mode_support == "enable" &&
      aws_route.firewall_to_transit_gateway["us-east-1a"].transit_gateway_id == "tgw-0123456789abcdef0" &&
      aws_route.runner_to_firewall["us-east-1a"].vpc_endpoint_id == "vpce-00000000000000001"
    )
    error_message = "Transit Gateway routes must use an appliance-mode attachment spanning the selected availability zones."
  }

  assert {
    condition = (
      aws_route.egress_to_runner["us-east-1b:us-east-1a"].destination_cidr_block == "100.64.0.0/18" &&
      aws_route.egress_to_runner["us-east-1b:us-east-1a"].vpc_endpoint_id == "vpce-00000000000000002"
    )
    error_message = "return traffic from the Transit Gateway attachment must cross the same-zone firewall endpoint."
  }
}

run "firewall_can_be_disabled_in_nat_gateway_mode" {
  command = plan

  variables {
    enable_firewall = false
  }

  assert {
    condition = (
      length(aws_subnet.firewall) == 0 &&
      length(aws_route_table.firewall) == 0 &&
      length(aws_networkfirewall_firewall.this) == 0 &&
      length(aws_networkfirewall_firewall_policy.default) == 0 &&
      length(aws_networkfirewall_rule_group.allowed_domains) == 0 &&
      length(aws_networkfirewall_rule_group.control_manifest_reject) == 0 &&
      length(aws_networkfirewall_logging_configuration.this) == 0 &&
      length(aws_cloudwatch_log_group.network_firewall_flow) == 0 &&
      length(aws_cloudwatch_log_group.network_firewall_alert) == 0
    )
    error_message = "disabling the firewall must omit its subnets, resources, policy, logging configuration, and log groups."
  }

  assert {
    condition = (
      aws_route.runner_to_nat["us-east-1a"].nat_gateway_id == aws_nat_gateway.this["us-east-1a"].id &&
      length(aws_route.runner_to_firewall) == 0 &&
      length(aws_route.egress_to_runner) == 0
    )
    error_message = "without a firewall, runner subnets must route directly to the same-zone NAT Gateway."
  }

  assert {
    condition     = output.network_firewall_arn == null
    error_message = "the firewall ARN must be null when the firewall is disabled."
  }

  assert {
    condition     = length(output.network_firewall_endpoint_ids) == 0 && length(output.firewall_subnet_ids) == 0
    error_message = "firewall endpoint and subnet outputs must be empty when the firewall is disabled."
  }

  assert {
    condition     = length(output.cloudwatch_log_group_names) == 2
    error_message = "VPC and Resolver log groups must remain available when the firewall is disabled."
  }
}

run "firewall_can_be_disabled_in_transit_gateway_mode" {
  command = plan

  variables {
    enable_firewall = false
    egress = {
      mode               = "transit_gateway"
      transit_gateway_id = "tgw-0123456789abcdef0"
    }
  }

  assert {
    condition = (
      aws_ec2_transit_gateway_vpc_attachment.this[0].appliance_mode_support == "disable" &&
      aws_route.runner_to_transit_gateway["us-east-1b"].transit_gateway_id == "tgw-0123456789abcdef0" &&
      length(aws_route.runner_to_firewall) == 0 &&
      length(aws_route.firewall_to_transit_gateway) == 0 &&
      length(aws_route.egress_to_runner) == 0
    )
    error_message = "without a firewall, runner subnets must route directly to the Transit Gateway."
  }
}

run "three_availability_zones_keep_a_spare_runner_range" {
  command = plan

  variables {
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  assert {
    condition = output.runner_subnet_cidrs == {
      "us-east-1a" = "100.64.0.0/19"
      "us-east-1b" = "100.64.32.0/19"
      "us-east-1c" = "100.64.64.0/19"
    }
    error_message = "three-AZ deployments must create one /19 runner subnet per availability zone."
  }

  assert {
    condition = (
      length(aws_route.egress_to_runner) == 9 &&
      aws_route.egress_to_runner["us-east-1c:us-east-1b"].destination_cidr_block == "100.64.32.0/19" &&
      aws_route.egress_to_runner["us-east-1c:us-east-1b"].vpc_endpoint_id == "vpce-00000000000000003"
    )
    error_message = "each egress route table must route every exact runner subnet CIDR through its same-zone firewall endpoint."
  }

  assert {
    condition     = output.runner_reserved_cidrs == ["100.64.128.0/17", "100.64.96.0/19"]
    error_message = "three-AZ deployments must expose both the reserved half and spare fourth /19."
  }
}

run "transit_gateway_mode_requires_a_gateway" {
  command = plan

  variables {
    egress = {
      mode = "transit_gateway"
    }
  }

  expect_failures = [var.egress]
}

run "network_requires_two_or_three_availability_zones" {
  command = plan

  variables {
    availability_zones = ["us-east-1a"]
  }

  expect_failures = [var.availability_zones]
}

run "routable_range_must_leave_room_for_subnet_tiers" {
  command = plan

  variables {
    routable_vpc_cidr = "10.42.0.0/25"
  }

  expect_failures = [var.routable_vpc_cidr]
}

run "firewall_domain_allowlist_rejects_urls" {
  command = plan

  variables {
    firewall_allowed_domains = ["https://github.com/path"]
  }

  expect_failures = [var.firewall_allowed_domains]
}

run "firewall_domain_allowlist_rejects_asterisk_wildcards" {
  command = plan

  variables {
    firewall_allowed_domains = ["*.example.com"]
  }

  expect_failures = [var.firewall_allowed_domains]
}

run "custom_yaml_replaces_baseline_and_normalizes_domains" {
  command = plan

  variables {
    firewall_config_path = "./tests/fixtures/firewall-custom.yaml"
  }

  assert {
    condition = (
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets == toset(["packages.example.com", ".corp.example"]) &&
      length(aws_networkfirewall_rule_group.control_manifest_reject) == 1 &&
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_default_actions == toset(["aws:drop_established", "aws:alert_established"])
    )
    error_message = "a custom YAML file must replace the baseline, normalize hostnames, and retain SNI inspection."
  }
}

run "explicit_manifest_allowlisting_is_preserved" {
  command = plan

  variables {
    firewall_allowed_domains = ["CONTAINERS.DEV"]
  }

  assert {
    condition = (
      length(aws_networkfirewall_rule_group.control_manifest_reject) == 0 &&
      length(aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_rule_group_reference) == 1 &&
      contains(aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets, "containers.dev")
    )
    error_message = "an explicitly allowed manifest hostname must remain allowed after normalization."
  }
}

run "custom_yaml_can_allow_the_manifest_domain_and_subdomains" {
  command = plan

  variables {
    firewall_config_path = "tests/fixtures/firewall-allow-control-manifest.yaml"
  }

  assert {
    condition = (
      length(aws_networkfirewall_rule_group.control_manifest_reject) == 0 &&
      length(aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_rule_group_reference) == 1 &&
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets == toset([".containers.dev"])
    )
    error_message = "a caller-owned YAML allowlist covering the manifest hostname must not be overridden by rejection."
  }
}

run "manifest_rejection_tracks_custom_runner_subnets" {
  command = plan

  variables {
    runner_cgnat_cidr        = "100.80.0.0/16"
    availability_zones       = ["us-east-1a", "us-east-1b", "us-east-1c"]
    firewall_allowed_domains = ["sub.containers.dev", "containers.dev.example.com"]
  }

  assert {
    condition = (
      length(aws_networkfirewall_rule_group.control_manifest_reject) == 1 &&
      toset(one(aws_networkfirewall_rule_group.control_manifest_reject[0].rule_group[0].rule_variables[0].ip_sets).ip_set[0].definition) == toset(["100.80.0.0/19", "100.80.32.0/19", "100.80.64.0/19"])
    )
    error_message = "rejection must cover every configured runner subnet, and allowing a different hostname must not disable it."
  }
}

run "custom_yaml_accepts_an_absolute_path" {
  command = plan

  variables {
    firewall_config_path = abspath("tests/fixtures/firewall-custom.yaml")
  }

  assert {
    condition     = aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets == toset(["packages.example.com", ".corp.example"])
    error_message = "absolute caller-owned file paths must work without resolving against the downloaded module."
  }
}

run "empty_custom_yaml_denies_all_firewall_routed_traffic" {
  command = plan

  variables {
    firewall_config_path = "tests/fixtures/firewall-empty.yaml"
  }

  assert {
    condition = (
      length(aws_networkfirewall_rule_group.allowed_domains) == 0 &&
      length(aws_networkfirewall_rule_group.control_manifest_reject) == 0 &&
      length(aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_rule_group_reference) == 0 &&
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_default_actions == toset(["aws:drop_strict", "aws:alert_strict"]) &&
      aws_route.runner_to_firewall["us-east-1a"].vpc_endpoint_id == "vpce-00000000000000001"
    )
    error_message = "an explicitly empty YAML allowlist must deny all inspected traffic without bypassing the firewall."
  }
}

run "custom_yaml_cannot_be_combined_with_additions" {
  command = plan

  variables {
    firewall_config_path     = "tests/fixtures/firewall-custom.yaml"
    firewall_allowed_domains = ["other.example.com"]
  }

  expect_failures = [aws_networkfirewall_firewall.this[0]]
}

run "custom_yaml_cannot_be_combined_with_a_policy_arn" {
  command = plan

  variables {
    firewall_config_path = "tests/fixtures/does-not-exist.yaml"
    firewall_policy_arn  = "arn:aws:network-firewall:us-east-1:123456789012:firewall-policy/customer-policy"
  }

  expect_failures = [aws_networkfirewall_firewall.this[0]]
}

run "disabled_firewall_ignores_unused_yaml" {
  command = plan

  variables {
    enable_firewall      = false
    firewall_config_path = "tests/fixtures/does-not-exist.yaml"
  }

  assert {
    condition     = length(aws_networkfirewall_firewall_policy.default) == 0 && length(aws_networkfirewall_rule_group.allowed_domains) == 0
    error_message = "a disabled firewall must not read or validate an unused configuration file."
  }
}

run "empty_yaml_path_is_rejected" {
  command = plan

  variables {
    firewall_config_path = " "
  }

  expect_failures = [var.firewall_config_path]
}

run "custom_yaml_rejects_unknown_key" {
  command = plan

  variables {
    firewall_config_path = "tests/fixtures/firewall-unknown-key.yaml"
  }

  expect_failures = [aws_networkfirewall_firewall_policy.default[0]]
}

run "custom_yaml_rejects_nonstring" {
  command = plan

  variables {
    firewall_config_path = "tests/fixtures/firewall-nonstring.yaml"
  }

  expect_failures = [aws_networkfirewall_firewall_policy.default[0]]
}

run "custom_yaml_rejects_invalid_hostname" {
  command = plan

  variables {
    firewall_config_path = "tests/fixtures/firewall-invalid-host.yaml"
  }

  expect_failures = [aws_networkfirewall_firewall_policy.default[0]]
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

  assert {
    condition = (
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_default_actions == toset(["aws:drop_established", "aws:alert_established"]) &&
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets == toset(local.firewall_config_domains)
    )
    error_message = "configuring an outbound proxy and CA bundle must not expand the baseline allowlist or remove default denial."
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

  assert {
    condition = (
      aws_networkfirewall_firewall_policy.default[0].firewall_policy[0].stateful_default_actions == toset(["aws:drop_established", "aws:alert_established"]) &&
      aws_networkfirewall_rule_group.allowed_domains[0].rule_group[0].rules_source[0].rules_source_list[0].targets == toset(local.firewall_config_domains) &&
      aws_vpc_endpoint.management_plane.service_name == local.management_plane_endpoint_service_name &&
      aws_vpc_endpoint.management_plane.private_dns_enabled
    )
    error_message = "a custom API endpoint must not alter the default firewall policy or management-plane PrivateLink endpoint."
  }
}
