resource "aws_vpc" "this" {
  cidr_block           = var.routable_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = var.name })
}

resource "aws_vpc_ipv4_cidr_block_association" "runner" {
  vpc_id     = aws_vpc.this.id
  cidr_block = var.runner_cgnat_cidr
}

resource "aws_subnet" "runner" {
  for_each = local.runner_subnet_cidrs

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                  = "${var.name}-runner-${each.key}"
    "ona.com/subnet-tier" = "runner"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.runner]
}

resource "aws_subnet" "firewall" {
  for_each = local.firewall_subnet_cidrs

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                  = "${var.name}-firewall-${each.key}"
    "ona.com/subnet-tier" = "firewall"
  })
}

resource "aws_subnet" "egress" {
  for_each = local.egress_subnet_cidrs

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                  = "${var.name}-${replace(var.egress.mode, "_", "-")}-${each.key}"
    "ona.com/subnet-tier" = var.egress.mode
  })
}

resource "aws_route_table" "runner" {
  for_each = local.availability_zone_indices

  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-runner-${each.key}" })
}

resource "aws_route_table" "firewall" {
  for_each = local.firewall_subnet_cidrs

  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-firewall-${each.key}" })
}

resource "aws_route_table" "egress" {
  for_each = local.availability_zone_indices

  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-egress-${each.key}" })
}

resource "aws_route_table_association" "runner" {
  for_each = local.availability_zone_indices

  subnet_id      = aws_subnet.runner[each.key].id
  route_table_id = aws_route_table.runner[each.key].id
}

resource "aws_route_table_association" "firewall" {
  for_each = local.firewall_subnet_cidrs

  subnet_id      = aws_subnet.firewall[each.key].id
  route_table_id = aws_route_table.firewall[each.key].id
}

resource "aws_route_table_association" "egress" {
  for_each = local.availability_zone_indices

  subnet_id      = aws_subnet.egress[each.key].id
  route_table_id = aws_route_table.egress[each.key].id
}

resource "aws_internet_gateway" "this" {
  count = var.egress.mode == "nat_gateway" ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = var.name })
}

resource "aws_eip" "nat" {
  for_each = var.egress.mode == "nat_gateway" ? local.availability_zone_indices : {}

  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.name}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = var.egress.mode == "nat_gateway" ? local.availability_zone_indices : {}

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.egress[each.key].id
  tags          = merge(local.common_tags, { Name = "${var.name}-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.egress.mode == "transit_gateway" ? 1 : 0

  subnet_ids             = [for zone in var.availability_zones : aws_subnet.egress[zone].id]
  transit_gateway_id     = var.egress.transit_gateway_id
  vpc_id                 = aws_vpc.this.id
  appliance_mode_support = var.enable_firewall ? "enable" : "disable"
  dns_support            = "enable"
  ipv6_support           = "disable"

  tags = merge(local.common_tags, { Name = var.name })
}

resource "aws_route" "runner_to_firewall" {
  for_each = var.enable_firewall ? local.availability_zone_indices : {}

  route_table_id         = aws_route_table.runner[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_ids[each.key]
}

resource "aws_route" "runner_to_nat" {
  for_each = !var.enable_firewall && var.egress.mode == "nat_gateway" ? local.availability_zone_indices : {}

  route_table_id         = aws_route_table.runner[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route" "runner_to_transit_gateway" {
  for_each = !var.enable_firewall && var.egress.mode == "transit_gateway" ? local.availability_zone_indices : {}

  route_table_id         = aws_route_table.runner[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.egress.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route" "firewall_to_nat" {
  for_each = var.enable_firewall && var.egress.mode == "nat_gateway" ? local.availability_zone_indices : {}

  route_table_id         = aws_route_table.firewall[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route" "firewall_to_transit_gateway" {
  for_each = var.enable_firewall && var.egress.mode == "transit_gateway" ? local.availability_zone_indices : {}

  route_table_id         = aws_route_table.firewall[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.egress.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route" "egress_to_internet_gateway" {
  for_each = var.egress.mode == "nat_gateway" ? local.availability_zone_indices : {}

  route_table_id         = aws_route_table.egress[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route" "egress_to_runner" {
  for_each = var.enable_firewall ? local.egress_to_runner_routes : {}

  route_table_id         = aws_route_table.egress[each.value.egress_zone].id
  destination_cidr_block = local.runner_subnet_cidrs[each.value.runner_zone]
  vpc_endpoint_id        = local.firewall_endpoint_ids[each.value.egress_zone]
}
