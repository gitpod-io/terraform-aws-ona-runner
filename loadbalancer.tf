resource "aws_lb" "proxy" {
  name               = "${local.load_balancer_name_prefix}-runner"
  load_balancer_type = "network"
  internal           = var.load_balancer_scheme == "internal"
  subnets            = var.load_balancer_subnet_ids
  security_groups    = [local.load_balancer_security_group_id_effective]
  ip_address_type    = "ipv4"

  enable_cross_zone_load_balancing = true

  tags = local.common_tags
}

resource "aws_lb_target_group" "proxy" {
  name                 = "${local.target_group_name_prefix}-proxy"
  port                 = 8443
  protocol             = "TLS"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 120
  preserve_client_ip   = true

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "5000"
    path                = "/_health"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "proxy_tls" {
  load_balancer_arn = aws_lb.proxy.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  alpn_policy       = "HTTP2Preferred"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }

  tags = local.common_tags
}
