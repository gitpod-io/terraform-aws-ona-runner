locals {
  create_alias_records = var.create_alias_records && var.load_balancer_dns_name != "" && var.load_balancer_zone_id != ""

  validation_options_by_record_name = {
    for option in aws_acm_certificate.runner.domain_validation_options :
    option.resource_record_name => option...
  }

  validation_records = {
    for record_name, options in local.validation_options_by_record_name :
    record_name => {
      name   = options[0].resource_record_name
      record = options[0].resource_record_value
      type   = options[0].resource_record_type
    }
  }
}

resource "aws_acm_certificate" "runner" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = !var.create_alias_records || ((var.load_balancer_dns_name == "") == (var.load_balancer_zone_id == ""))
      error_message = "load_balancer_dns_name and load_balancer_zone_id must either both be set or both be empty when create_alias_records is true."
    }
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_records

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
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
