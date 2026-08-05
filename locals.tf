data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name_prefix = lower(var.runner_name)

  memorydb_name_prefix           = substr(local.name_prefix, 0, 31)
  memorydb_subnet_name_prefix    = substr(local.name_prefix, 0, 40)
  memorydb_user_name_prefix      = substr(local.name_prefix, 0, 26)
  memorydb_acl_name_prefix       = substr(local.name_prefix, 0, 27)
  elasticache_name_prefix        = substr(local.name_prefix, 0, 34)
  elasticache_subnet_name_prefix = substr(local.name_prefix, 0, 38)
  load_balancer_name_prefix      = substr(local.name_prefix, 0, 25)
  target_group_name_prefix       = substr(local.name_prefix, 0, 26)
  s3_bucket_name_prefix          = substr(local.name_prefix, 0, 25)
  iam_role_name_prefix           = substr(local.name_prefix, 0, 24)

  common_tags = merge(var.tags, {
    "aws-apn-id"                           = "pc:7fmtjv5ewmq6d8gwjb08fwitz"
    "gitpod:terraform:module"              = "terraform-aws-ona-runner"
    "gitpod:cloudformation:stack-provider" = "gitpod-flex"
    "gitpod.dev/runner-id"                 = var.runner_id
  })

  runner_owned_resource_tag_keys = [
    "aws-apn-id",
    "gitpod.dev/runner-id",
  ]

  runner_resource_tags = {
    for key, value in local.common_tags : key => value
    if !contains(local.runner_owned_resource_tag_keys, key)
  }

  runner_is_large = var.runner_size == "large"

  non_graviton_cache_region = contains(["eu-west-3", "eu-south-2"], data.aws_region.current.name)
  elasticache_node_type = local.runner_is_large ? (
    local.non_graviton_cache_region ? "cache.r5.large" : "cache.r7g.large"
    ) : (
    local.non_graviton_cache_region ? "cache.t3.small" : "cache.t4g.small"
  )
  memorydb_node_type = local.runner_is_large ? "db.t4g.medium" : "db.t4g.small"

  runner_token_secret_name = "${data.aws_region.current.name}-${var.runner_id}-runner-token"
  runner_token_secret_arn  = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${local.runner_token_secret_name}-??????"

  # Legacy name-based runner token secret. The daemon is launched with
  # --old-runner-token-secret pointing here (see ecs.tf) and reads it on startup
  # to migrate the token to the new runner_id-based secret. The CloudFormation
  # deployment grants the task role access to this ARN (see EcsRoles in
  # runner/ec2/deploy/pkg/ecs/ecs.go, "kept so the daemon retains access during
  # rollback or partial migration"); this keeps the Terraform module at parity.
  old_runner_token_secret_arn = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${data.aws_region.current.name}-${local.name_prefix}-runner-token-??????"
  redis_parameter_name        = "/gitpod/runner/${var.runner_id}/ai-execution-redis"
  runner_config_key           = "/gitpod/runner/${var.runner_id}"

  proxy_env = compact([
    try(var.proxy_config.http_proxy, "") == "" ? "" : "http_proxy=${var.proxy_config.http_proxy}",
    try(var.proxy_config.https_proxy, "") == "" ? "" : "https_proxy=${var.proxy_config.https_proxy}",
    try(var.proxy_config.all_proxy, "") == "" ? "" : "all_proxy=${var.proxy_config.all_proxy}",
    try(var.proxy_config.no_proxy, "") == "" ? "" : "no_proxy=${var.proxy_config.no_proxy}",
  ])

  # Keep this order aligned with config.Runner in gitpod-next. The runner
  # rewrites this SSM value with encoding/json and Terraform compares raw bytes.
  runner_config = join("", concat([
    "{",
    "\"awsAccountId\":", jsonencode(data.aws_caller_identity.current.account_id),
    ",\"resourceTableName\":", jsonencode(aws_dynamodb_table.resources.name),
    ",\"vpcId\":", jsonencode(var.vpc_id),
    ",\"stackName\":", jsonencode(local.name_prefix),
    ",\"runnerLogGroup\":", jsonencode(aws_cloudwatch_log_group.runner.name),
    ",\"proxyLogGroup\":", jsonencode(aws_cloudwatch_log_group.proxy.name),
    ",\"adotLogGroup\":", jsonencode(aws_cloudwatch_log_group.adot.name),
    ",\"subnetIDs\":", jsonencode(join(" ", var.runner_subnet_ids)),
    ",\"securityGroupId\":", jsonencode(aws_security_group.environment.id),
    ",\"instanceProfileName\":", jsonencode(aws_iam_instance_profile.environment.name),
    ",\"environmentRoleArn\":", jsonencode(aws_iam_role.environment.arn),
    ",\"apiEndpoint\":", jsonencode(var.api_endpoint),
    ",\"exchangeToken\":", jsonencode(var.runner_token),
    ], var.default_ami == "" ? [] : [
    ",\"defaultAMI\":", jsonencode(var.default_ami),
    ], [
    ",\"gatewayAPIEndpoint\":", jsonencode(var.gateway_api_endpoint),
    ",\"infrastructureVersion\":\"terraform\"",
    ",\"sshPort\":29222",
    ",\"resourceTags\":", jsonencode(local.runner_resource_tags),
    ",\"cacheBucketName\":", jsonencode(aws_s3_bucket.container_registry.bucket),
    ",\"logsBucket\":", jsonencode(aws_s3_bucket.logs.bucket),
    ",\"agentBucketName\":", jsonencode(aws_s3_bucket.agent.bucket),
    ",\"logLevel\":\"info\"",
    ",\"devContainerCacheRegistryAccessRoleArn\":", jsonencode(aws_iam_role.devcontainer_cache_registry_access.arn),
    ",\"sshOverGateway\":\"true\"",
    ",\"runnerProxyDomain\":", jsonencode(var.runner_domain),
    ",\"runnerPackage\":\"Enterprise\"",
    ",\"runnerTemplateBuildVersion\":", jsonencode(var.runner_template_build_version),
    ",\"asgWarmPoolEnabled\":true",
    ",\"horizontalScalingEnabled\":true",
    "}",
  ]))
}
