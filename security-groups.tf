resource "aws_security_group" "ecs" {
  name_prefix = "${local.name_prefix}-ecs-"
  description = "Security group for Ona Runner ECS tasks"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs" })
}

resource "aws_security_group" "load_balancer" {
  count       = var.load_balancer_security_group_id == "" ? 1 : 0
  name_prefix = "${local.name_prefix}-nlb-"
  description = "Security group for the Ona Runner Network Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nlb" })
}

locals {
  load_balancer_security_group_id_effective = var.load_balancer_security_group_id == "" ? aws_security_group.load_balancer[0].id : var.load_balancer_security_group_id
}

resource "aws_security_group_rule" "ecs_from_load_balancer" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  source_security_group_id = local.load_balancer_security_group_id_effective
  protocol                 = "tcp"
  from_port                = 1024
  to_port                  = 65535
  description              = "Allow traffic from runner load balancer"
}

resource "aws_security_group_rule" "ecs_portspec_self" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs.id
  self              = true
  protocol          = "tcp"
  from_port         = 7070
  to_port           = 7070
  description       = "Allow proxy to reach runner port spec endpoint"
}

resource "aws_security_group_rule" "ecs_runner_api_self" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs.id
  self              = true
  protocol          = "tcp"
  from_port         = 8081
  to_port           = 8081
  description       = "Allow Service Connect traffic to runner API"
}

resource "aws_security_group_rule" "ecs_runner_metrics_self" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs.id
  self              = true
  protocol          = "tcp"
  from_port         = 9090
  to_port           = 9090
  description       = "Allow ADOT to scrape runner metrics"
}

resource "aws_security_group_rule" "ecs_proxy_metrics_self" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs.id
  self              = true
  protocol          = "tcp"
  from_port         = 9094
  to_port           = 9094
  description       = "Allow ADOT to scrape proxy metrics"
}

resource "aws_security_group" "environment" {
  name_prefix = "${local.name_prefix}-env-"
  description = "Default security group for Ona environment instances"
  vpc_id      = var.vpc_id

  ingress {
    security_groups = [aws_security_group.ecs.id]
    protocol        = "tcp"
    from_port       = 1024
    to_port         = 65535
    description     = "Allow runner ECS tasks to connect to environments"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-environment" })
}
