resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.network_name}-vpce-"
  description = "Allows restricted Ona runner services to reach VPC endpoints."
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.network_name}-vpc-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_runner" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = module.runner.runner_ecs_security_group_id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
  description                  = "Allow HTTPS from runner ECS tasks."
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_environments" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = module.runner.environment_security_group_id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
  description                  = "Allow HTTPS from environment EC2 instances."
}

resource "aws_vpc_endpoint" "aws_interface" {
  for_each = local.aws_interface_endpoint_services

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for zone in var.availability_zones : aws_subnet.runner[zone].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.network_name}-${replace(each.key, ".", "-")}" })
}

resource "aws_vpc_endpoint" "aws_gateway" {
  for_each = local.aws_gateway_endpoint_services

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for zone in var.availability_zones : aws_route_table.runner[zone].id]

  tags = merge(local.common_tags, { Name = "${local.network_name}-${each.key}" })
}

resource "aws_vpc_endpoint" "management_plane" {
  vpc_id              = aws_vpc.this.id
  service_name        = local.management_plane_endpoint_service_name
  service_region      = var.aws_region == local.management_plane_endpoint_service_region ? null : local.management_plane_endpoint_service_region
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for zone in local.management_plane_endpoint_zones : aws_subnet.runner[zone].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.network_name}-management-plane" })
}
