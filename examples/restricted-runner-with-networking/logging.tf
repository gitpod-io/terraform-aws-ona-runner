data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "network_firewall_flow" {
  count = var.enable_firewall ? 1 : 0

  name              = "/aws/ona/${local.network_name}/network-firewall/flow"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "network_firewall_alert" {
  count = var.enable_firewall ? 1 : 0

  name              = "/aws/ona/${local.network_name}/network-firewall/alert"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/aws/ona/${local.network_name}/vpc-flow"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "resolver_queries" {
  name              = "/aws/ona/${local.network_name}/resolver-queries"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_arn
  tags              = local.common_tags
}

resource "aws_networkfirewall_logging_configuration" "this" {
  count = var.enable_firewall ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.this[0].arn

  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall_flow[0].name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall_alert[0].name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }
  }
}

data "aws_iam_policy_document" "vpc_flow_logs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name_prefix        = "${local.network_name}-flow-"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "vpc_flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow.arn}:*"]
  }

  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name_prefix = "${local.network_name}-flow-"
  role        = aws_iam_role.vpc_flow_logs.id
  policy      = data.aws_iam_policy_document.vpc_flow_logs.json
}

resource "aws_flow_log" "vpc" {
  iam_role_arn             = aws_iam_role.vpc_flow_logs.arn
  log_destination          = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = 60
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.this.id

  tags = local.common_tags
}

data "aws_iam_policy_document" "resolver_query_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.resolver_queries.arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["route53resolver.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:route53resolver:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:resolver-query-log-config/*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "resolver_query_logs" {
  policy_name     = "${local.network_name}-resolver-queries"
  policy_document = data.aws_iam_policy_document.resolver_query_logs.json
}

resource "aws_route53_resolver_query_log_config" "this" {
  name            = "${local.network_name}-resolver-queries"
  destination_arn = aws_cloudwatch_log_group.resolver_queries.arn
  tags            = local.common_tags

  depends_on = [aws_cloudwatch_log_resource_policy.resolver_query_logs]
}

resource "aws_route53_resolver_query_log_config_association" "this" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.this.id
  resource_id                  = aws_vpc.this.id
}
