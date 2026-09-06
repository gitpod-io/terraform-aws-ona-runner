locals {
  network_name = var.network_name != null ? var.network_name : "${trimsuffix(substr(lower(var.runner_name), 0, 12), "-")}-${substr(sha256(lower(var.runner_id)), 0, 16)}"

  availability_zone_indices = {
    for index, zone in var.availability_zones : zone => index
  }

  runner_active_cidr   = cidrsubnet(var.runner_cgnat_cidr, 1, 0)
  runner_reserved_cidr = cidrsubnet(var.runner_cgnat_cidr, 1, 1)
  runner_subnet_bits   = length(var.availability_zones) == 2 ? 1 : 2
  runner_subnet_cidrs = {
    for zone, index in local.availability_zone_indices :
    zone => cidrsubnet(local.runner_active_cidr, local.runner_subnet_bits, index)
  }
  runner_spare_cidrs = length(var.availability_zones) == 3 ? [cidrsubnet(local.runner_active_cidr, 2, 3)] : []

  firewall_subnet_cidrs = {
    for zone, index in local.availability_zone_indices :
    zone => cidrsubnet(var.routable_vpc_cidr, 4, index)
    if var.enable_firewall
  }
  egress_subnet_cidrs = {
    for zone, index in local.availability_zone_indices :
    zone => cidrsubnet(var.routable_vpc_cidr, 4, 4 + index)
  }
  egress_to_runner_routes = {
    for pair in setproduct(var.availability_zones, var.availability_zones) :
    "${pair[0]}:${pair[1]}" => {
      egress_zone = pair[0]
      runner_zone = pair[1]
    }
  }

  common_tags = merge(var.tags, {
    "ona.com/component" = "runner-networking"
  })

  firewall_policy_arn = var.enable_firewall ? coalesce(var.firewall_policy_arn, aws_networkfirewall_firewall_policy.default[0].arn) : null
  firewall_endpoint_ids = var.enable_firewall ? {
    for zone in var.availability_zones : zone => one([
      for state in aws_networkfirewall_firewall.this[0].firewall_status[0].sync_states :
      state.attachment[0].endpoint_id if state.availability_zone == zone
    ])
  } : {}
}
