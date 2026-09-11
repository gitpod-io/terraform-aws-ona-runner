variable "external_credential_proxy_ers_upstream" {
  description = "Trusted HTTPS ERS API base. Empty disables the external credential proxy. Requires a runner image with credential-proxy support."
  type        = string
  default     = ""
  validation {
    condition     = var.external_credential_proxy_ers_upstream == "" || can(regex("^https://[^?#@ ]+/api$", var.external_credential_proxy_ers_upstream))
    error_message = "Use an HTTPS API base ending in /api, without credentials, query or fragment."
  }
}

locals {
  external_credentials_enabled = var.external_credential_proxy_ers_upstream != ""
  external_credential_hostname = "credentials.${local.internal_runner_namespace}"
  external_credential_endpoint = "https://${local.external_credential_hostname}:8443"
  external_credential_config_fragments = local.external_credentials_enabled ? [
    ",\"externalCredentialProxy\":", jsonencode({
      endpoint        = local.external_credential_endpoint
      issuerSecretARN = aws_secretsmanager_secret.external_credential_issuer[0].arn
      proxySecretARN  = aws_secretsmanager_secret.external_credential_proxy[0].arn
    }),
  ] : []
  external_credential_log_options = {
    awslogs-group         = try(aws_cloudwatch_log_group.external_credentials[0].name, "")
    awslogs-region        = data.aws_region.current.name
    awslogs-stream-prefix = "credential-proxy"
  }
}

resource "aws_secretsmanager_secret" "external_credential_issuer" {
  count       = local.external_credentials_enabled ? 1 : 0
  name_prefix = "${local.name_prefix}-external-credential-issuer-"
  description = "Runner-owned Environment client signing authority"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret" "external_credential_proxy" {
  count       = local.external_credentials_enabled ? 1 : 0
  name_prefix = "${local.name_prefix}-external-credential-proxy-"
  description = "Proxy server key and public Environment client authority"
  tags        = local.common_tags
}

resource "aws_service_discovery_service" "external_credentials" {
  count = local.external_credentials_enabled ? 1 : 0
  name  = "credentials"
  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.internal_runner[0].id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
  tags = local.common_tags
}

data "aws_iam_policy_document" "external_credentials" {
  count = local.external_credentials_enabled ? 1 : 0
  statement {
    sid       = "ReadProxyMaterial"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.external_credential_proxy[0].arn]
  }
  statement {
    sid       = "ReadCustomTrustBundle"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::gitpod-*/*"]
  }
}

resource "aws_iam_role" "external_credentials" {
  count              = local.external_credentials_enabled ? 1 : 0
  name_prefix        = "${local.iam_role_name_prefix}-credentials-"
  assume_role_policy = data.aws_iam_policy_document.fargate_task_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "external_credentials" {
  count  = local.external_credentials_enabled ? 1 : 0
  role   = aws_iam_role.external_credentials[0].id
  policy = data.aws_iam_policy_document.external_credentials[0].json
}

resource "aws_iam_role" "external_credentials_execution" {
  count              = local.external_credentials_enabled ? 1 : 0
  name_prefix        = "${local.iam_role_name_prefix}-cred-exec-"
  assume_role_policy = data.aws_iam_policy_document.fargate_task_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "external_credentials_execution" {
  count      = local.external_credentials_enabled ? 1 : 0
  role       = aws_iam_role.external_credentials_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "external_credentials_execution" {
  count = local.external_credentials_enabled ? 1 : 0
  statement {
    sid       = "PullThroughCache"
    actions   = ["ecr:BatchImportUpstreamImage"]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }
}

resource "aws_iam_role_policy" "external_credentials_execution" {
  count  = local.external_credentials_enabled ? 1 : 0
  role   = aws_iam_role.external_credentials_execution[0].id
  policy = data.aws_iam_policy_document.external_credentials_execution[0].json
}

resource "aws_security_group" "external_credentials" {
  count       = local.external_credentials_enabled ? 1 : 0
  name_prefix = "${local.name_prefix}-credentials-"
  description = "External credential proxy tasks"
  vpc_id      = var.vpc_id
  tags        = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "external_credentials" {
  count             = local.external_credentials_enabled ? 1 : 0
  security_group_id = aws_security_group.external_credentials[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "external_credential_data" {
  count                        = local.external_credentials_enabled ? 1 : 0
  security_group_id            = aws_security_group.external_credentials[0].id
  referenced_security_group_id = aws_security_group.environment.id
  ip_protocol                  = "tcp"
  from_port                    = 8443
  to_port                      = 8443
}

resource "aws_vpc_security_group_ingress_rule" "external_credential_lookup" {
  count                        = local.external_credentials_enabled ? 1 : 0
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.external_credentials[0].id
  ip_protocol                  = "tcp"
  from_port                    = 7072
  to_port                      = 7072
}

resource "aws_vpc_security_group_ingress_rule" "external_credential_health" {
  count                        = local.external_credentials_enabled ? 1 : 0
  security_group_id            = aws_security_group.external_credentials[0].id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 9092
  to_port                      = 9092
}

resource "aws_cloudwatch_log_group" "external_credentials" {
  count             = local.external_credentials_enabled ? 1 : 0
  name              = "/gitpod/external-credentials/${local.name_prefix}"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "external_credentials" {
  count                    = local.external_credentials_enabled ? 1 : 0
  family                   = "${local.name_prefix}-credentials"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  lifecycle {
    precondition {
      condition     = !var.restrict_ingress || var.internal_llm_proxy_port != 7072
      error_message = "The internal LLM proxy port must differ from the external credential binding port 7072."
    }
  }
  execution_role_arn = aws_iam_role.external_credentials_execution[0].arn
  task_role_arn      = aws_iam_role.external_credentials[0].arn
  container_definitions = jsonencode([
    merge(local.ca_init_container, { logConfiguration = { logDriver = "awslogs", options = local.external_credential_log_options } }),
    {
      name                   = "credential-proxy"
      image                  = local.runner_image
      essential              = true
      readonlyRootFilesystem = true
      command = [
        "credential-proxy", "--material-secret-arn", aws_secretsmanager_secret.external_credential_proxy[0].arn,
        "--server-name", local.external_credential_hostname,
        "--lookup-endpoint", "http://runner.${local.internal_runner_namespace}:7072",
        "--ers-upstream", var.external_credential_proxy_ers_upstream,
      ]
      environment = concat([{ name = "AWS_REGION", value = data.aws_region.current.name }], [for value in local.proxy_env : { name = split("=", value)[0], value = join("=", slice(split("=", value), 1, length(split("=", value)))) }])
      stopTimeout = 60
      dependsOn   = local.ca_dependency
      mountPoints = local.ca_mount
      portMappings = [
        { containerPort = 8443, protocol = "tcp" },
        { containerPort = 9092, protocol = "tcp" },
      ]
      healthCheck      = { command = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:9092/healthz || exit 1"], interval = 10, timeout = 5, retries = 3, startPeriod = 60 }
      logConfiguration = { logDriver = "awslogs", options = local.external_credential_log_options }
    }
  ])
  dynamic "volume" {
    for_each = local.ca_volumes
    content { name = volume.value.name }
  }
  tags = local.common_tags
}

resource "aws_ecs_service" "external_credentials" {
  count                              = local.external_credentials_enabled ? 1 : 0
  name                               = "${local.name_prefix}-credentials"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.external_credentials[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  wait_for_steady_state              = true
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = local.task_network_configuration.subnets
    security_groups  = [aws_security_group.external_credentials[0].id]
    assign_public_ip = local.task_network_configuration.assign_public_ip
  }
  service_registries { registry_arn = aws_service_discovery_service.external_credentials[0].arn }
  depends_on = [aws_ecs_service.runner, aws_iam_role_policy.external_credentials, aws_iam_role_policy_attachment.external_credentials_execution]
  tags       = local.common_tags
}

output "external_credential_proxy_endpoint" {
  description = "Private mTLS credential proxy endpoint, or null when disabled."
  value       = local.external_credentials_enabled ? local.external_credential_endpoint : null
}
