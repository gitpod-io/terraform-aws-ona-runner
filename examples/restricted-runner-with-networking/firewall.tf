locals {
  firewall_baseline_domains = toset(yamldecode(file("${path.module}/firewall.yaml")).allowed_domains)
  firewall_allowed_domains = toset([
    for domain in setunion(local.firewall_baseline_domains, var.firewall_allowed_domains) : lower(domain)
  ])
}

resource "aws_networkfirewall_rule_group" "allowed_domains" {
  count = var.enable_firewall && var.firewall_policy_arn == null ? 1 : 0

  capacity    = 1000
  name        = "${local.network_name}-allowed-domains"
  description = "HTTPS domains allowed from Ona runner subnets."
  type        = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"

        ip_set {
          definition = [var.routable_vpc_cidr, var.runner_cgnat_cidr]
        }
      }
    }

    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI"]
        targets              = local.firewall_allowed_domains
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = length(local.firewall_allowed_domains) <= 999
      error_message = "The baseline and additional firewall domains must contain at most 999 distinct hostnames combined."
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "default" {
  count = var.enable_firewall && var.firewall_policy_arn == null ? 1 : 0

  name        = "${local.network_name}-default"
  description = "Default-deny policy for Ona runner egress inspection."

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions = [
      "aws:drop_established",
      "aws:alert_established",
    ]

    dynamic "stateful_rule_group_reference" {
      for_each = aws_networkfirewall_rule_group.allowed_domains

      content {
        priority     = 100
        resource_arn = stateful_rule_group_reference.value.arn
      }
    }

    policy_variables {
      rule_variables {
        key = "HOME_NET"

        ip_set {
          definition = [var.routable_vpc_cidr, var.runner_cgnat_cidr]
        }
      }
    }

    stateful_engine_options {
      rule_order              = "STRICT_ORDER"
      stream_exception_policy = "DROP"
    }
  }

  tags = local.common_tags
}

resource "aws_networkfirewall_firewall" "this" {
  count = var.enable_firewall ? 1 : 0

  name                = local.network_name
  firewall_policy_arn = local.firewall_policy_arn
  vpc_id              = aws_vpc.this.id

  delete_protection                 = false
  firewall_policy_change_protection = false
  subnet_change_protection          = false

  dynamic "subnet_mapping" {
    for_each = local.availability_zone_indices

    content {
      subnet_id = aws_subnet.firewall[subnet_mapping.key].id
    }
  }

  tags = local.common_tags
}
