output "aws_account_id" {
  description = "AWS account ID to register in Ona custom-domain settings."
  value       = data.aws_caller_identity.current.account_id
}

output "domain_name" {
  description = "Configured management-plane domain name."
  value       = var.domain_name
}

output "vscode_domain_name" {
  description = "VS Code Browser domain name that must point to the same load balancer."
  value       = "vscode.${var.domain_name}"
}

output "load_balancer_arn" {
  description = "ARN of the custom-domain Network Load Balancer."
  value       = aws_lb.this.arn
}

output "load_balancer_dns_name" {
  description = "DNS name that domain_name and vscode_domain_name must resolve to."
  value       = aws_lb.this.dns_name
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID for Route53 alias records targeting the load balancer."
  value       = aws_lb.this.zone_id
}

output "load_balancer_security_group_id" {
  description = "Security group ID of the custom-domain Network Load Balancer."
  value       = aws_security_group.load_balancer.id
}

output "vpc_endpoint_id" {
  description = "ID of the VPC endpoint connected to the Ona relay service."
  value       = aws_vpc_endpoint.relay.id
}

output "vpc_endpoint_ip_addresses" {
  description = "Private IP addresses registered as load-balancer targets."
  value       = [for interface in data.aws_network_interface.relay : interface.private_ip]
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID of the Ona relay VPC endpoint."
  value       = aws_security_group.vpc_endpoint.id
}
