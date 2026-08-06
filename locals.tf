data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  runner_name_prefix    = trimsuffix(substr(lower(var.runner_name), 0, 12), "-")
  runner_id_name_suffix = substr(sha256(lower(var.runner_id)), 0, 16)
  default_name_prefix   = "${local.runner_name_prefix}-${local.runner_id_name_suffix}"
  name_prefix           = coalesce(var.resource_name_prefix, local.default_name_prefix)

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

  redis_parameter_name = "/gitpod/runner/${var.runner_id}/ai-execution-redis"
  runner_config_key    = "/gitpod/runner/${var.runner_id}"

  release_public_ecr_prefix = "public.ecr.aws/k5t9d3j5/application/gitpod-next"
  release_runner_image = var.runner_image != "" ? var.runner_image : (
    "${local.release_public_ecr_prefix}/gitpod-ec2-runner:${var.runner_template_build_version}"
  )
  release_proxy_image = var.proxy_image != "" ? var.proxy_image : (
    "${local.release_public_ecr_prefix}/gitpod-proxy:${var.runner_template_build_version}"
  )
  release_inputs_are_consistent = endswith(local.release_runner_image, ":${var.runner_template_build_version}") && endswith(local.release_proxy_image, ":${var.runner_template_build_version}")

  # CloudFormation private-ECR templates replace the runner image with this
  # prefix. Derive it from that existing release input so private-ECR users do
  # not need a Terraform-only configuration value for runner updates.
  private_ecr_prefix = can(regex("^([^/]+\\.dkr\\.ecr\\.[^.]+\\.amazonaws\\.com/gitpod/ecr)/", var.runner_image)) ? regex("^([^/]+\\.dkr\\.ecr\\.[^.]+\\.amazonaws\\.com/gitpod/ecr)/", var.runner_image)[0] : ""

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
