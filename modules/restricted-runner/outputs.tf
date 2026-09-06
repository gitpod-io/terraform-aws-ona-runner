output "runner_config_parameter_name" {
  description = "SSM parameter name containing runner configuration."
  value       = module.runner.runner_config_parameter_name
}

output "runner_token_secret_arn" {
  description = "Secrets Manager secret ARN pattern for the runner-created token secret."
  value       = module.runner.runner_token_secret_arn
}

output "runner_ecs_security_group_id" {
  description = "Security group ID of the runner ECS tasks."
  value       = module.runner.runner_ecs_security_group_id
}

output "environment_security_group_id" {
  description = "Security group ID for environment instances."
  value       = module.runner.environment_security_group_id
}

output "environment_instance_profile_name" {
  description = "Instance profile name for environment instances."
  value       = module.runner.environment_instance_profile_name
}

output "environment_role_arn" {
  description = "IAM role ARN for environment instances."
  value       = module.runner.environment_role_arn
}

output "s3_access_role_arn" {
  description = "IAM role ARN used for S3 cache access."
  value       = module.runner.s3_access_role_arn
}

output "devcontainer_cache_registry_access_role_arn" {
  description = "IAM role ARN used for devcontainer cache registry access."
  value       = module.runner.devcontainer_cache_registry_access_role_arn
}

output "container_registry_bucket_name" {
  description = "S3 bucket used for container registry cache blobs."
  value       = module.runner.container_registry_bucket_name
}

output "agent_bucket_name" {
  description = "S3 bucket used for agent execution data."
  value       = module.runner.agent_bucket_name
}

output "logs_bucket_name" {
  description = "S3 bucket used for environment logs and metrics audit data."
  value       = module.runner.logs_bucket_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table name used by the runner resource reconciler."
  value       = module.runner.dynamodb_table_name
}

output "redis_parameter_name" {
  description = "SSM parameter storing the AI execution cache connection string."
  value       = module.runner.redis_parameter_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name for runner tasks."
  value       = module.runner.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS service name for the Fargate runner task."
  value       = module.runner.ecs_service_name
}

output "adot_ecs_service_name" {
  description = "ECS service name for the Fargate telemetry task."
  value       = module.runner.adot_ecs_service_name
}

output "release_version" {
  description = "Runner template build version installed by this module."
  value       = module.runner.release_version
}

output "ssh_port" {
  description = "SSH port used by environment instances."
  value       = module.runner.ssh_port
}
