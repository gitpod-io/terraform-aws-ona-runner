output "vpc_id" {
  description = "ID of the runner VPC."
  value       = module.restricted_networking.vpc_id
}

output "runner_subnet_ids" {
  description = "Runner subnet IDs."
  value       = module.restricted_networking.runner_subnet_ids
}

output "network_firewall_arn" {
  description = "ARN of the egress Network Firewall, or null when disabled."
  value       = module.restricted_networking.network_firewall_arn
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs by availability zone, or an empty map in Transit Gateway mode."
  value       = module.restricted_networking.nat_gateway_ids
}

output "transit_gateway_vpc_attachment_id" {
  description = "Transit Gateway VPC attachment ID, or null in NAT Gateway mode."
  value       = module.restricted_networking.transit_gateway_vpc_attachment_id
}

output "runner_reserved_cidrs" {
  description = "CGNAT ranges deliberately reserved without subnets."
  value       = module.restricted_networking.runner_reserved_cidrs
}

output "cloudwatch_log_group_names" {
  description = "CloudWatch log groups for Network Firewall, VPC, and Resolver telemetry."
  value       = module.restricted_networking.cloudwatch_log_group_names
}
