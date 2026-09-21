locals {
  firewall_managed     = var.enable_firewall && var.firewall_policy_arn == null
  firewall_config_file = coalesce(var.firewall_config_path, "${path.module}/firewall.yaml")
  firewall_config      = local.firewall_managed ? yamldecode(file(local.firewall_config_file)) : null
  firewall_config_domains = {
    for role in ["runner", "environment"] : role => local.firewall_managed ? (
      contains(keys(local.firewall_config), "allowed_domains") ? local.firewall_config.allowed_domains : local.firewall_config["${role}_allowed_domains"]
    ) : []
  }
  firewall_allowed_domains = {
    for role, domains in local.firewall_config_domains : role => toset([
      for domain in concat(domains, tolist(var.firewall_allowed_domains)) : lower(domain)
    ])
  }
  firewall_source_arns = local.firewall_managed ? {
    runner      = aws_networkfirewall_container_association.runner[0].container_association_arn
    environment = aws_resourcegroups_group.environments[0].arn
  } : {}
  # Index 0 and its AWS name are retained from the original shared allowlist.
  firewall_rule_groups = local.firewall_managed ? [for index, role in ["runner", "environment"] : {
    name       = role == "runner" ? "${local.network_name}-allowed-domains" : "${local.network_name}-environment-domains"
    role       = role
    domains    = local.firewall_allowed_domains[role]
    source_arn = local.firewall_source_arns[role]
    priority   = (index + 1) * 100
  }] : []
}

resource "aws_networkfirewall_container_association" "runner" {
  count = local.firewall_managed ? 1 : 0

  container_association_name = "${local.network_name}-runner"
  type                       = "ECS"

  # Fargate requires an unfiltered association; the cluster is dedicated to this runner.
  container_monitoring_configuration {
    cluster_arn = module.runner.ecs_cluster_arn
  }

  tags = local.common_tags
}

resource "aws_resourcegroups_group" "environments" {
  count = local.firewall_managed ? 1 : 0

  name = "ona-${local.network_name}-environments"

  configuration {
    type = "AWS::NetworkFirewall::RuleGroup"
  }

  resource_query {
    type = "TAG_FILTERS_1_0"
    query = jsonencode({
      ResourceTypeFilters = ["AWS::EC2::Instance"]
      TagFilters = [
        { Key = "gitpod.dev/runner-id", Values = [var.runner_id] },
        { Key = "gitpod.dev/environment-id" },
      ]
    })
  }

  tags = local.common_tags
}

resource "aws_networkfirewall_rule_group" "allowed_domains" {
  count = length(local.firewall_rule_groups)

  capacity    = 1000
  name        = local.firewall_rule_groups[count.index].name
  description = "TLS domains allowed from Ona ${local.firewall_rule_groups[count.index].role} IPs."
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

    # AWS requires container and resource-group references to use separate rule groups.
    reference_sets {
      ip_set_references {
        key = "SOURCE_IPS"
        ip_set_reference {
          reference_arn = local.firewall_rule_groups[count.index].source_arn
        }
      }
    }

    rules_source {
      rules_string = length(local.firewall_rule_groups[count.index].domains) == 0 ? (
        "drop ip @SOURCE_IPS any -> $EXTERNAL_NET any (sid:${local.firewall_rule_groups[count.index].priority * 10000}; rev:1;)"
        ) : join("\n", [
          for index, domain in sort(tolist(local.firewall_rule_groups[count.index].domains)) : format(
            "pass tls @SOURCE_IPS any -> $EXTERNAL_NET any (ssl_state:client_hello; tls.sni; %scontent:\"%s\"; %sendswith; nocase; flow:to_server,established; sid:%d; rev:1;)",
            startswith(domain, ".") ? "dotprefix; " : "", domain,
            startswith(domain, ".") ? "" : "startswith; ",
            local.firewall_rule_groups[count.index].priority * 10000 + index + 1,
          )
      ])
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = length(local.firewall_rule_groups[count.index].domains) <= 999
      error_message = "Each firewall allowlist must contain at most 999 distinct hostnames, including any baseline and additional domains."
    }
  }
}

resource "aws_networkfirewall_rule_group" "control_manifest_reject" {
  count = (
    length(aws_networkfirewall_rule_group.allowed_domains) > 0 &&
    anytrue([for domains in values(local.firewall_allowed_domains) : length(domains) > 0]) &&
    alltrue([for domains in values(local.firewall_allowed_domains) :
      !contains(domains, "containers.dev") && !contains(domains, ".containers.dev")
    ])
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
      rules_string = "reject tls $HOME_NET any -> any 443 (ssl_state:client_hello; tls.sni; content:\"containers.dev\"; startswith; endswith; nocase; flow:to_server,established; msg:\"Reject devcontainer control manifest fetch\"; sid:500001; rev:1;)"
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
    stateful_default_actions = anytrue([for domains in values(local.firewall_allowed_domains) : length(domains) > 0]) ? [
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
        priority     = local.firewall_rule_groups[stateful_rule_group_reference.key].priority
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
      condition = (
        toset(keys(local.firewall_config)) == toset(["allowed_domains"]) ||
        toset(keys(local.firewall_config)) == toset(["runner_allowed_domains", "environment_allowed_domains"])
      )
      error_message = "Firewall YAML must contain either allowed_domains, or both runner_allowed_domains and environment_allowed_domains. Do not mix these forms or add other keys."
    }

    precondition {
      condition = alltrue([for domains in values(local.firewall_config_domains) : alltrue([
        for domain in domains :
        domain == tostring(domain) && length(domain) <= 253 &&
        can(regex("^\\.?([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", domain))
      ])])
      error_message = "Firewall domain lists must contain valid hostname strings, optionally prefixed with a dot for subdomains."
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
