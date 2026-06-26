data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "bottlerocket_ami" {
  count = var.bottlerocket_ami_id == "" ? 1 : 0
  name  = "/aws/service/bottlerocket/aws-ecs-1/x86_64/latest/image_id"
}

locals {
  name_prefix = substr(replace(lower(var.runner_name), "/[^a-z0-9-]/", "-"), 0, 32)

  common_tags = merge(var.tags, {
    "aws-apn-id"                           = "pc:7fmtjv5ewmq6d8gwjb08fwitz"
    "gitpod:terraform:module"              = "terraform-aws-ona-runner"
    "gitpod:cloudformation:stack-provider" = "gitpod-flex"
    "gitpod.dev/runner-id"                 = var.runner_id
  })

  runner_is_large = var.runner_size == "large"

  bottlerocket_ami_id = var.bottlerocket_ami_id == "" ? data.aws_ssm_parameter.bottlerocket_ami[0].value : var.bottlerocket_ami_id

  ecs_instance_type = local.runner_is_large ? (
    data.aws_region.current.name == "eu-south-2" ? "c7i.2xlarge" : "c6i.2xlarge"
    ) : (
    data.aws_region.current.name == "eu-south-2" ? "c7i.large" : "c6i.large"
  )

  runner_memory_reservation = local.runner_is_large ? 14336 : 1024
  autoscaling_max_size      = 1

  non_graviton_cache_region = contains(["eu-west-3", "eu-south-2"], data.aws_region.current.name)
  elasticache_node_type = local.runner_is_large ? (
    local.non_graviton_cache_region ? "cache.r5.large" : "cache.r7g.large"
    ) : (
    local.non_graviton_cache_region ? "cache.t3.small" : "cache.t4g.small"
  )
  memorydb_node_type = local.runner_is_large ? "db.t4g.medium" : "db.t4g.small"

  runner_token_secret_name = "${data.aws_region.current.name}-${var.runner_id}-runner-token"
  redis_parameter_name     = "/gitpod/runner/${var.runner_id}/ai-execution-redis"
  runner_config_key        = "/gitpod/runner/${var.runner_id}"

  proxy_env = compact([
    try(var.proxy_config.http_proxy, "") == "" ? "" : "http_proxy=${var.proxy_config.http_proxy}",
    try(var.proxy_config.https_proxy, "") == "" ? "" : "https_proxy=${var.proxy_config.https_proxy}",
    try(var.proxy_config.all_proxy, "") == "" ? "" : "all_proxy=${var.proxy_config.all_proxy}",
    try(var.proxy_config.no_proxy, "") == "" ? "" : "no_proxy=${var.proxy_config.no_proxy}",
  ])

  runner_config = {
    exchangeToken                          = var.runner_token
    apiEndpoint                            = var.api_endpoint
    awsAccountId                           = data.aws_caller_identity.current.account_id
    vpcId                                  = var.vpc_id
    stackName                              = local.name_prefix
    subnetIDs                              = join(" ", var.runner_subnet_ids)
    instanceProfileName                    = aws_iam_instance_profile.environment.name
    securityGroupId                        = aws_security_group.environment.id
    resourceTableName                      = aws_dynamodb_table.resources.name
    gatewayAPIEndpoint                     = var.gateway_api_endpoint
    infrastructureVersion                  = "terraform"
    sshPort                                = 29222
    cacheBucketName                        = aws_s3_bucket.container_registry.bucket
    runnerProxyDomain                      = var.runner_domain
    sshOverGateway                         = "true"
    runnerPackage                          = "Enterprise"
    runnerTemplateBuildVersion             = "__EC2_RUNNER_VERSION__"
    asgWarmPoolEnabled                     = true
    horizontalScalingEnabled               = true
    agentBucketName                        = aws_s3_bucket.agent.bucket
    logsBucket                             = aws_s3_bucket.logs.bucket
    environmentRoleArn                     = aws_iam_role.environment.arn
    runnerLogGroup                         = aws_cloudwatch_log_group.runner.name
    proxyLogGroup                          = aws_cloudwatch_log_group.runner.name
    devContainerCacheRegistryAccessRoleArn = aws_iam_role.devcontainer_cache_registry_access.arn
    defaultAMI                             = var.default_ami
  }
}
