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

output "ecs_execution_role_arn" {
  description = "Effective IAM role ARN for ecs execution."
  value       = module.runner.ecs_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "Effective IAM role ARN for ecs task."
  value       = module.runner.ecs_task_role_arn
}

output "proxy_role_arn" {
  description = "Effective IAM role ARN for proxy."
  value       = module.runner.proxy_role_arn
}

output "adot_role_arn" {
  description = "Effective IAM role ARN for adot."
  value       = module.runner.adot_role_arn
}

output "environment_role_arn" {
  description = "Effective IAM role ARN for environment."
  value       = module.runner.environment_role_arn
}

output "s3_access_role_arn" {
  description = "Effective IAM role ARN for s3 access."
  value       = module.runner.s3_access_role_arn
}

output "devcontainer_cache_registry_access_role_arn" {
  description = "Effective IAM role ARN for devcontainer cache registry access."
  value       = module.runner.devcontainer_cache_registry_access_role_arn
}
