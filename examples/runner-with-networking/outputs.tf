output "load_balancer_dns_name" {
  description = "DNS name to target from runner_domain and wildcard runner domain records."
  value       = module.runner.load_balancer_dns_name
}

output "runner_config_parameter_name" {
  description = "SSM runner config parameter name."
  value       = module.runner.runner_config_parameter_name
}

output "environment_instance_profile_name" {
  description = "Instance profile used by environment instances."
  value       = module.runner.environment_instance_profile_name
}
