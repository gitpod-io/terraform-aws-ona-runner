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
}

mock_provider "random" {}

variables {
  aws_region         = "us-east-1"
  runner_id          = "019d6999-807b-7e52-ab6f-c9202f13ecf2"
  runner_token       = "test-token"
  availability_zones = ["us-east-1a", "us-east-1b"]
  routable_vpc_cidr  = "10.42.0.0/24"
}

run "nat_gateway_mode_is_zonal_and_symmetric" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.42.0.0/24" && aws_vpc_ipv4_cidr_block_association.runner.cidr_block == "100.64.0.0/16"
    error_message = "the VPC must use the routable range as primary and the CGNAT range as secondary."
  }

  assert {
    condition     = aws_networkfirewall_firewall.this[0].name == "ona-runner-2ec33d556332a866"
    error_message = "the default network name must derive from runner_name and the full runner ID."
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
