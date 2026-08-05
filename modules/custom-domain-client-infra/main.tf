locals {
  create_alias_records = var.create_alias_records && var.load_balancer_dns_name != ""
}

resource "aws_acm_certificate" "runner" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.runner.domain_validation_options :
    option.resource_record_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }...
  }

  zone_id = var.hosted_zone_id
  name    = each.value[0].name
  type    = each.value[0].type
  ttl     = 300
  records = [each.value[0].record]
}

resource "aws_acm_certificate_validation" "runner" {
  certificate_arn         = aws_acm_certificate.runner.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

resource "aws_route53_record" "runner" {
  count   = local.create_alias_records ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wildcard" {
  count   = local.create_alias_records ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = false
  }
}
