output "runner_config_parameter_name" {
  description = "SSM parameter name containing runner configuration."
  value       = aws_ssm_parameter.runner_config.name
}

output "runner_token_secret_arn" {
  description = "Secrets Manager secret ARN containing the runner token."
  value       = aws_secretsmanager_secret.runner_token.arn
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
  value       = aws_iam_instance_profile.environment.name
}

output "environment_role_arn" {
  description = "IAM role ARN for environment instances."
  value       = aws_iam_role.environment.arn
}

output "s3_access_role_arn" {
  description = "IAM role ARN used for S3 cache access."
  value       = aws_iam_role.s3_access.arn
}

output "devcontainer_cache_registry_access_role_arn" {
  description = "IAM role ARN used for devcontainer cache registry access."
  value       = aws_iam_role.devcontainer_cache_registry_access.arn
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
  description = "DNS name of the runner proxy Network Load Balancer."
  value       = aws_lb.proxy.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the runner proxy Network Load Balancer."
  value       = aws_lb.proxy.arn
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the runner proxy Network Load Balancer."
  value       = aws_lb.proxy.zone_id
}

output "load_balancer_security_group_id" {
  description = "Security group ID used by the runner proxy Network Load Balancer."
  value       = local.load_balancer_security_group_id_effective
}

output "ecs_cluster_name" {
  description = "ECS cluster name for runner tasks."
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name for the runner task."
  value       = aws_ecs_service.runner.name
}

output "ecs_auto_scaling_group_name" {
  description = "Auto Scaling Group name for ECS instances."
  value       = aws_autoscaling_group.ecs.name
}

output "ssh_port" {
  description = "SSH port used by environment instances."
  value       = 29222
}
