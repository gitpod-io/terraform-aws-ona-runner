output "runner_config_parameter_name" {
  description = "SSM parameter name containing runner configuration."
  value       = aws_ssm_parameter.runner_config.name
}

output "runner_token_secret_arn" {
  description = "Secrets Manager secret ARN pattern for the runner-created token secret."
  value       = local.runner_token_secret_arn
}

output "runner_ecs_security_group_id" {
  description = "Security group ID of the runner ECS tasks."
  value       = aws_security_group.ecs.id
}

output "environment_security_group_id" {
  description = "Security group ID for environment instances."
  value       = aws_security_group.environment.id
}

output "environment_instance_profile_name" {
  description = "Instance profile name for environment instances."
  value       = local.environment_instance_profile_name
}

output "environment_role_arn" {
  description = "IAM role ARN for environment instances."
  value       = local.environment_role_arn
}

output "s3_access_role_arn" {
  description = "IAM role ARN used for S3 cache access."
  value       = local.s3_access_role_arn
}

output "devcontainer_cache_registry_access_role_arn" {
  description = "IAM role ARN used for devcontainer cache registry access."
  value       = local.devcontainer_cache_registry_access_role_arn
}

output "container_registry_bucket_name" {
  description = "S3 bucket used for container registry cache blobs."
  value       = aws_s3_bucket.container_registry.bucket
}

output "agent_bucket_name" {
  description = "S3 bucket used for agent execution data."
  value       = aws_s3_bucket.agent.bucket
}

output "logs_bucket_name" {
  description = "S3 bucket used for environment logs and metrics audit data."
  value       = aws_s3_bucket.logs.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table name used by the runner resource reconciler."
  value       = aws_dynamodb_table.resources.name
}

output "redis_parameter_name" {
  description = "SSM parameter storing the AI execution cache connection string."
  value       = aws_ssm_parameter.redis_connection.name
}

output "load_balancer_dns_name" {
  description = "DNS name of the runner proxy Network Load Balancer, or null when ingress is restricted."
  value       = var.restrict_ingress ? null : aws_lb.proxy[0].dns_name
}

output "load_balancer_arn" {
  description = "ARN of the runner proxy Network Load Balancer, or null when ingress is restricted."
  value       = var.restrict_ingress ? null : aws_lb.proxy[0].arn
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the runner proxy Network Load Balancer, or null when ingress is restricted."
  value       = var.restrict_ingress ? null : aws_lb.proxy[0].zone_id
}

output "load_balancer_security_group_id" {
  description = "Security group ID used by the runner proxy Network Load Balancer, or null when ingress is restricted."
  value       = local.load_balancer_security_group_id_effective
}

output "ecs_cluster_name" {
  description = "ECS cluster name for runner tasks."
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name for the Fargate runner task."
  value       = aws_ecs_service.runner.name
}

output "proxy_ecs_service_name" {
  description = "ECS service name for the Fargate proxy task, or null when ingress is restricted."
  value       = var.restrict_ingress ? null : aws_ecs_service.proxy[0].name
}

output "adot_ecs_service_name" {
  description = "ECS service name for the Fargate telemetry task."
  value       = aws_ecs_service.adot.name
}

output "release_version" {
  description = "Runner template build version installed by this module."
  value       = var.runner_template_build_version
}

output "ssh_port" {
  description = "SSH port used by environment instances."
  value       = 29222
}

output "ecs_execution_role_arn" {
  description = "Effective IAM role ARN for ecs execution."
  value       = local.ecs_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "Effective IAM role ARN for ecs task."
  value       = local.ecs_task_role_arn
}

output "proxy_role_arn" {
  description = "Effective IAM role ARN for proxy. Null when ingress is restricted."
  value       = local.proxy_role_arn
}

output "adot_role_arn" {
  description = "Effective IAM role ARN for adot."
  value       = local.adot_role_arn
}
