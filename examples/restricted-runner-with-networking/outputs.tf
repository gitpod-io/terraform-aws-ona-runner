output "vpc_id" {
  description = "ID of the runner VPC."
  value       = aws_vpc.this.id
}

output "runner_subnet_ids" {
  description = "Runner subnet IDs ordered to match availability_zones."
  value       = [for zone in var.availability_zones : aws_subnet.runner[zone].id]
}

output "runner_subnet_cidrs" {
  description = "Runner subnet CIDRs keyed by availability zone."
  value       = local.runner_subnet_cidrs
}

output "runner_active_cidr" {
  description = "Half of runner_cgnat_cidr allocated to runner subnets."
  value       = local.runner_active_cidr
}

output "runner_reserved_cidrs" {
  description = "CGNAT ranges deliberately left without subnets. Three-AZ deployments include the unused fourth subnet-sized range from the active half."
  value       = concat([local.runner_reserved_cidr], local.runner_spare_cidrs)
}

output "firewall_subnet_ids" {
  description = "Dedicated Network Firewall subnet IDs ordered to match availability_zones. Empty when the firewall is disabled."
  value       = var.enable_firewall ? [for zone in var.availability_zones : aws_subnet.firewall[zone].id] : []
}

output "egress_subnet_ids" {
  description = "NAT Gateway or Transit Gateway attachment subnet IDs ordered to match availability_zones."
  value       = [for zone in var.availability_zones : aws_subnet.egress[zone].id]
}

output "network_firewall_arn" {
  description = "ARN of the Network Firewall, or null when the firewall is disabled."
  value       = try(aws_networkfirewall_firewall.this[0].arn, null)
}

output "network_firewall_policy_arn" {
  description = "ARN of the Network Firewall policy used by the firewall, or null when the firewall is disabled."
  value       = local.firewall_policy_arn
}

output "network_firewall_endpoint_ids" {
  description = "Network Firewall endpoint IDs keyed by availability zone. Empty when the firewall is disabled."
  value       = local.firewall_endpoint_ids
}

output "aws_interface_vpc_endpoint_ids" {
  description = "Interface VPC endpoint IDs keyed by AWS service name."
  value       = { for service, endpoint in aws_vpc_endpoint.aws_interface : service => endpoint.id }
}

output "aws_gateway_vpc_endpoint_ids" {
  description = "Gateway VPC endpoint IDs keyed by AWS service name."
  value       = { for service, endpoint in aws_vpc_endpoint.aws_gateway : service => endpoint.id }
}

output "management_plane_vpc_endpoint_id" {
  description = "Interface VPC endpoint ID whose private DNS name resolves app.gitpod.io."
  value       = aws_vpc_endpoint.management_plane.id
}

output "vpc_endpoint_security_group_id" {
  description = "Security group allowing the runner subnet CIDRs to reach interface VPC endpoints over HTTPS."
  value       = aws_security_group.vpc_endpoints.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs keyed by availability zone. Empty in Transit Gateway mode."
  value       = { for zone, gateway in aws_nat_gateway.this : zone => gateway.id }
}

output "transit_gateway_vpc_attachment_id" {
  description = "Transit Gateway VPC attachment ID, or null in NAT Gateway mode."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.this[0].id, null)
}

output "cloudwatch_log_group_names" {
  description = "CloudWatch log groups created for network telemetry."
  value = merge({
    resolver_queries = aws_cloudwatch_log_group.resolver_queries.name
    vpc_flow         = aws_cloudwatch_log_group.vpc_flow.name
    }, var.enable_firewall ? {
    network_firewall_alert = aws_cloudwatch_log_group.network_firewall_alert[0].name
    network_firewall_flow  = aws_cloudwatch_log_group.network_firewall_flow[0].name
  } : {})
}

output "runner_config_parameter_name" {
  description = "SSM runner config parameter name."
  value       = module.runner.runner_config_parameter_name
}

output "environment_instance_profile_name" {
  description = "Instance profile used by environment instances."
  value       = module.runner.environment_instance_profile_name
}
