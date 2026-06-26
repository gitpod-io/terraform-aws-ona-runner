output "certificate_arn" {
  description = "ACM certificate ARN for the runner domain."
  value       = aws_acm_certificate_validation.runner.certificate_arn
}

output "domain_name" {
  description = "Configured runner domain name."
  value       = var.domain_name
}

output "validation_record_fqdns" {
  description = "DNS validation record FQDNs."
  value       = [for record in aws_route53_record.validation : record.fqdn]
}

output "runner_record_fqdn" {
  description = "Runner domain alias record FQDN."
  value       = local.create_alias_records ? aws_route53_record.runner[0].fqdn : ""
}

output "wildcard_record_fqdn" {
  description = "Wildcard runner domain alias record FQDN."
  value       = local.create_alias_records ? aws_route53_record.wildcard[0].fqdn : ""
}
