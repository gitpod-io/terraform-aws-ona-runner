locals {
  firewall_managed        = var.enable_firewall && var.firewall_policy_arn == null
  firewall_config_file    = coalesce(var.firewall_config_path, "${path.module}/firewall.yaml")
  firewall_config         = local.firewall_managed ? yamldecode(file(local.firewall_config_file)) : null
  firewall_config_domains = local.firewall_managed ? local.firewall_config.allowed_domains : []
  firewall_allowed_domains = toset([
    for domain in concat(local.firewall_config_domains, tolist(var.firewall_allowed_domains)) : lower(domain)
  ])
}

resource "aws_networkfirewall_rule_group" "allowed_domains" {
  count = local.firewall_managed && (var.firewall_config_path == null || length(local.firewall_config_domains) > 0) ? 1 : 0

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
      error_message = "The firewall allowlist must contain at most 999 distinct hostnames, including any baseline and additional domains."
    }
  }
}

resource "aws_networkfirewall_rule_group" "control_manifest_reject" {
  count = (
    length(aws_networkfirewall_rule_group.allowed_domains) > 0 &&
    !contains(local.firewall_allowed_domains, "containers.dev") &&
    !contains(local.firewall_allowed_domains, ".containers.dev")
  ) ? 1 : 0

  capacity    = 1
  name        = "${local.network_name}-control-manifest-reject"
  description = "Reject blocked devcontainer control manifest requests without a TCP timeout."
  type        = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"

        ip_set {
          definition = values(local.runner_subnet_cidrs)
        }
      }
    }

    rules_source {
      # Silent drops stall devcontainer startup; a reset lets the CLI use its manifest fallback.
      # https://github.com/microsoft/vscode-remote-release/issues/8808
      rules_string = "reject tls $HOME_NET any -> any 443 (ssl_state:client_hello; tls.sni; content:\"containers.dev\"; startswith; endswith; nocase; flow:to_server,established; msg:\"Reject devcontainer control manifest fetch\"; sid:1000001; rev:1;)"
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = local.common_tags
}

resource "aws_networkfirewall_firewall_policy" "default" {
  count = local.firewall_managed ? 1 : 0

  name        = "${local.network_name}-default"
  description = "Default-deny policy for Ona runner egress inspection."

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions = var.firewall_config_path == null || length(local.firewall_config_domains) > 0 ? [
      "aws:drop_established",
      "aws:alert_established",
      ] : [
      "aws:drop_strict",
      "aws:alert_strict",
    ]

    dynamic "stateful_rule_group_reference" {
      for_each = aws_networkfirewall_rule_group.control_manifest_reject

      content {
        priority     = 50
        resource_arn = stateful_rule_group_reference.value.arn
      }
    }

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

  lifecycle {
    precondition {
      condition     = toset(keys(local.firewall_config)) == toset(["allowed_domains"])
      error_message = "Firewall YAML must contain only the allowed_domains key."
    }

    precondition {
      condition = alltrue([
        for domain in local.firewall_config.allowed_domains :
        domain == tostring(domain) && length(domain) <= 253 &&
        can(regex("^\\.?([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", domain))
      ])
      error_message = "Firewall allowed_domains must contain valid hostname strings, optionally prefixed with a dot for subdomains."
    }
  }
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

  lifecycle {
    precondition {
      condition     = var.firewall_config_path == null || (var.firewall_policy_arn == null && length(var.firewall_allowed_domains) == 0)
      error_message = "firewall_config_path replaces the entire allowlist; do not combine it with firewall_policy_arn or non-empty firewall_allowed_domains."
    }
  }
}
