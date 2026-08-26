data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  subnet_indices = {
    for index, subnet_id in sort(tolist(var.subnet_ids)) : subnet_id => index
  }

  common_tags = merge(var.tags, {
    "ona.com/component" = "management-plane-custom-domain"
  })
}

resource "aws_security_group" "load_balancer" {
  name_prefix = "${var.service_name}-lb-"
  description = "Controls HTTPS access to the Ona custom-domain load balancer."
  vpc_id      = var.vpc_id
  tags        = local.common_tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(var.allowed_ipv4_cidr_blocks) > 0 || length(var.allowed_security_group_ids) > 0
      error_message = "At least one allowed_ipv4_cidr_blocks or allowed_security_group_ids entry is required."
    }
  }
}

resource "aws_security_group" "vpc_endpoint" {
  name_prefix = "${var.service_name}-vpce-"
  description = "Allows the custom-domain load balancer to reach the Ona relay VPC endpoint."
  vpc_id      = var.vpc_id
  tags        = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "load_balancer_ipv4" {
  for_each = var.allowed_ipv4_cidr_blocks

  security_group_id = aws_security_group.load_balancer.id
  cidr_ipv4         = each.value
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "load_balancer_security_group" {
  for_each = var.allowed_security_group_ids

  security_group_id            = aws_security_group.load_balancer.id
  referenced_security_group_id = each.value
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "load_balancer_to_vpc_endpoint" {
  security_group_id            = aws_security_group.load_balancer.id
  referenced_security_group_id = aws_security_group.vpc_endpoint.id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoint_from_load_balancer" {
  security_group_id            = aws_security_group.vpc_endpoint.id
  referenced_security_group_id = aws_security_group.load_balancer.id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
}

resource "aws_vpc_endpoint" "relay" {
  vpc_id            = var.vpc_id
  vpc_endpoint_type = "Interface"
  service_name      = var.endpoint_service_name
  service_region    = var.endpoint_service_region

  subnet_ids          = sort(tolist(var.subnet_ids))
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = false

  tags = local.common_tags
}

data "aws_network_interface" "relay" {
  for_each = local.subnet_indices

  id = tolist(aws_vpc_endpoint.relay.network_interface_ids)[each.value]
}

resource "aws_lb" "this" {
  name               = "${var.service_name}-lb"
  load_balancer_type = "network"
  internal           = var.load_balancer_scheme == "internal"
  subnets            = sort(tolist(var.subnet_ids))
  security_groups    = [aws_security_group.load_balancer.id]
  ip_address_type    = "ipv4"

  enable_cross_zone_load_balancing = true

  tags = local.common_tags
}

resource "aws_lb_target_group" "relay" {
  name        = "${var.service_name}-relay"
  port        = 443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  preserve_client_ip = false
  proxy_protocol_v2  = false

  health_check {
    enabled  = true
    protocol = "TCP"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group_attachment" "relay" {
  for_each = data.aws_network_interface.relay

  target_group_arn = aws_lb_target_group.relay.arn
  target_id        = each.value.private_ip
  port             = 443
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  alpn_policy       = "HTTP2Preferred"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.relay.arn
  }

  lifecycle {
    precondition {
      condition     = can(regex("^arn:[^:]+:acm:${data.aws_region.current.name}:[0-9]{12}:certificate/.+$", var.certificate_arn))
      error_message = "certificate_arn must identify an ACM certificate in the AWS provider region."
    }
  }

  tags = local.common_tags
}
