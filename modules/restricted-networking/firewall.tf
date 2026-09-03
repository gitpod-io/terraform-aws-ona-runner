resource "aws_networkfirewall_firewall_policy" "default" {
  count = var.enable_firewall && var.firewall_policy_arn == null ? 1 : 0

  name        = "${var.name}-default"
  description = "Permissive baseline policy for Ona runner egress inspection."

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions           = ["aws:alert_established"]

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

  name                = var.name
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
