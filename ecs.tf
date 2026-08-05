resource "aws_cloudwatch_log_group" "runner" {
  name              = "/gitpod/runner/${local.name_prefix}/${var.runner_id}"
  retention_in_days = 365
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/gitpod/runner-proxy/${local.name_prefix}/${var.runner_id}"
  retention_in_days = 365
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "adot" {
  name              = "/gitpod/runner-adot/${local.name_prefix}/${var.runner_id}"
  retention_in_days = 365
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-ona-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.this.arn
  }

  tags = local.common_tags
}

resource "aws_service_discovery_http_namespace" "this" {
  name = "ona-${var.runner_id}"
  tags = local.common_tags
}

locals {
  runner_task_cpu    = local.runner_is_large ? 4096 : 1024
  runner_task_memory = local.runner_is_large ? 16384 : 3072
  proxy_task_cpu     = local.runner_is_large ? 2048 : 512
  proxy_task_memory  = local.runner_is_large ? 4096 : 1024

  task_network_configuration = {
    subnets          = var.runner_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.assign_public_ip
  }

  runner_log_options = {
    awslogs-region        = data.aws_region.current.name
    awslogs-group         = aws_cloudwatch_log_group.runner.name
    awslogs-stream-prefix = "/gitpod/runner/${local.name_prefix}"
  }

  proxy_log_options = {
    awslogs-region        = data.aws_region.current.name
    awslogs-group         = aws_cloudwatch_log_group.proxy.name
    awslogs-stream-prefix = "/gitpod/runner-proxy/${local.name_prefix}"
  }

  adot_log_options = {
    awslogs-region        = data.aws_region.current.name
    awslogs-group         = aws_cloudwatch_log_group.adot.name
    awslogs-stream-prefix = "aws-otel-collector"
  }

  ca_volumes = [
    { name = "ca-certificates" },
    { name = "ca-init-tmp" },
    { name = "ca-init-ssl-certs" },
    { name = "ca-init-usr-local" },
  ]

  ca_init_mounts = [
    { sourceVolume = "ca-certificates", containerPath = "/shared-ca-certs", readOnly = false },
    { sourceVolume = "ca-init-tmp", containerPath = "/tmp", readOnly = false },
    { sourceVolume = "ca-init-ssl-certs", containerPath = "/etc/ssl/certs", readOnly = false },
    { sourceVolume = "ca-init-usr-local", containerPath = "/usr/local/share/ca-certificates", readOnly = false },
  ]

  ca_init_container = {
    name                   = "init-container"
    image                  = var.runner_image
    essential              = false
    memoryReservation      = 64
    readonlyRootFilesystem = true
    user                   = "root"
    entryPoint             = ["/bin/sh", "-c"]
    command                = ["update-ca-certificates && /app/gitpod-ec2-runner setup-ca"]
    environment = [
      { name = "AWS_REGION", value = data.aws_region.current.name },
      { name = "GITPOD_CUSTOM_CA_BUNDLE", value = var.custom_ca_trust_bundle },
    ]
    mountPoints = local.ca_init_mounts
  }

  ca_mount      = [{ sourceVolume = "ca-certificates", containerPath = "/etc/ssl/certs", readOnly = true }]
  ca_dependency = [{ containerName = "init-container", condition = "SUCCESS" }]

  adot_container = {
    name                   = "aws-otel-collector"
    image                  = var.adot_image
    essential              = true
    user                   = "0"
    readonlyRootFilesystem = true
    secrets                = [{ name = "AOT_CONFIG_CONTENT", valueFrom = aws_ssm_parameter.adot_config.arn }]
    mountPoints            = concat([{ sourceVolume = "adot-tmp", containerPath = "/config", readOnly = false }], local.ca_mount, [{ sourceVolume = "audit", containerPath = "/audit", readOnly = false }])
    dependsOn              = local.ca_dependency
    environment = [for item in local.proxy_env : {
      name = split("=", item)[0], value = join("=", slice(split("=", item), 1, length(split("=", item))))
    }]
    healthCheck = { command = ["CMD", "/healthcheck"], retries = 3, timeout = 5, interval = 30, startPeriod = 15 }
  }

  metrics_audit_sync_container = {
    name                   = "metrics-audit-sync"
    image                  = var.metrics_audit_sync_image
    essential              = false
    memoryReservation      = 64
    readonlyRootFilesystem = true
    entryPoint             = ["/bin/sh", "-c"]
    command = [<<-EOT
      while true; do
        for f in /audit/metrics-*.json; do
          [ -f "$$f" ] || continue
          key="metrics/runner/$${RUNNER_ID}/$$(date -u +%Y/%m/%d)/$$(basename "$$f")"
          if aws s3 cp "$$f" "s3://$${AUDIT_BUCKET}/$${key}" --quiet; then
            rm -f "$$f"
          fi
        done
        sleep 60
      done
    EOT
    ]
    mountPoints = concat(local.ca_mount, [
      { sourceVolume = "audit", containerPath = "/audit", readOnly = false },
      { sourceVolume = "audit-tmp", containerPath = "/tmp", readOnly = false },
    ])
    dependsOn = local.ca_dependency
    environment = concat([
      { name = "AUDIT_BUCKET", value = aws_s3_bucket.logs.bucket },
      { name = "AWS_CA_BUNDLE", value = "/etc/ssl/certs/ca-certificates.crt" },
      { name = "RUNNER_ID", value = var.runner_id },
      ], [for item in local.proxy_env : {
        name = split("=", item)[0], value = join("=", slice(split("=", item), 1, length(split("=", item))))
    }])
  }

  runner_container = {
    name                   = "ec2-runner"
    image                  = var.runner_image
    essential              = true
    memoryReservation      = local.runner_is_large ? 14336 : 128
    readonlyRootFilesystem = true
    command = [
      "daemon",
      "--ssm-key=${local.runner_config_key}",
      "--runner-token-secret=${local.runner_token_secret_name}",
      "--metrics-secret-arn=${aws_secretsmanager_secret.metrics_config.arn}",
      "--server-port=8081",
      "--enable-ai-execution-feature",
      "--ai-execution-redis-secret=${local.redis_parameter_name}",
      "--enable-llm-proxy",
      "--enable-environment-snapshots",
    ]
    environment = concat([
      { name = "AWS_REGION", value = data.aws_region.current.name },
      { name = "GITPOD_PRIVATE_ECR_PREFIX", value = "__GITPOD_PRIVATE_ECR_PREFIX__" },
      { name = "S3_ACCESS_ROLE_ARN", value = aws_iam_role.s3_access.arn },
      { name = "PORT_AUTHENTICATION_ENABLED", value = "true" },
      { name = "REDIS_CLUSTER_MODE", value = var.cache_engine == "MemoryDB" ? "true" : "false" },
      { name = "RUNNER_CONFIG_HASH", value = sha256(local.runner_config) },
      { name = "ADOT_CONFIG_SSM_PARAM", value = aws_ssm_parameter.adot_config.name },
      { name = "GITPOD_CUSTOM_CA_BUNDLE", value = var.custom_ca_trust_bundle },
      ], var.development_version == "" ? [] : [
      { name = "GITPOD_DEVELOPMENT_VERSION", value = var.development_version },
      ], [for item in local.proxy_env : {
        name = split("=", item)[0], value = join("=", slice(split("=", item), 1, length(split("=", item))))
    }])
    mountPoints = local.ca_mount
    dependsOn   = local.ca_dependency
    portMappings = [
      { name = "metrics", containerPort = 9090, protocol = "tcp" },
      { name = "runner-api", containerPort = 8081, protocol = "tcp" },
      { name = "portspec", containerPort = 7070, protocol = "tcp" },
    ]
    healthCheck = { command = ["CMD-SHELL", "/app/gitpod-ec2-runner ping"], retries = 3, timeout = 5, startPeriod = 10 }
  }

  proxy_container = {
    name                   = "proxy"
    image                  = var.proxy_image
    essential              = true
    memoryReservation      = 128
    readonlyRootFilesystem = true
    command = [
      "run-runner-proxy",
      "--runner-id=${var.runner_id}",
      "--public-domain=${var.runner_domain}",
      "--cert-dir=/app/certs",
      "--metrics-addr=:9094",
      "--http-port=8080",
      "--https-port=8443",
      "--runner-host=runner",
      "--runner-port=8081",
      "--management-plane-api-url=${var.api_endpoint}",
    ]
    environment = concat([
      { name = "AWS_REGION", value = data.aws_region.current.name },
      { name = "PORT_AUTHENTICATION_ENABLED", value = "true" },
      ], [for item in local.proxy_env : {
        name = split("=", item)[0], value = join("=", slice(split("=", item), 1, length(split("=", item))))
    }])
    mountPoints = concat(local.ca_mount, [{ sourceVolume = "proxy-config", containerPath = "/app/certs/", readOnly = false }])
    dependsOn   = local.ca_dependency
    portMappings = [
      { name = "proxy-metrics", containerPort = 9094, protocol = "tcp" },
      { name = "http", containerPort = 8080, protocol = "tcp" },
      { name = "https", containerPort = 8443, protocol = "tcp" },
      { name = "health", containerPort = 5000, protocol = "tcp" },
    ]
    healthCheck = { command = ["CMD-SHELL", "curl -f -k http://localhost:5000/_health || exit 1"], retries = 3, timeout = 5, interval = 30, startPeriod = 10 }
  }

  adot_default_config = <<-EOT
    extensions:
      health_check:
        endpoint: "0.0.0.0:13133"
    receivers:
      prometheus:
        config:
          scrape_configs:
            - job_name: placeholder
              static_configs:
                - targets: []
    exporters:
      debug:
        verbosity: basic
    service:
      extensions: [health_check]
      pipelines:
        metrics:
          receivers: [prometheus]
          exporters: [debug]
  EOT
}

resource "aws_ssm_parameter" "adot_config" {
  name  = "/gitpod/runner/${var.runner_id}/adot-config"
  type  = "String"
  value = local.adot_default_config
  tags  = local.common_tags
}

resource "aws_ecs_task_definition" "runner" {
  family                   = "${local.name_prefix}-runner"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.runner_task_cpu
  memory                   = local.runner_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode([
    merge(local.ca_init_container, { logConfiguration = { logDriver = "awslogs", options = local.runner_log_options } }),
    merge(local.runner_container, { logConfiguration = { logDriver = "awslogs", options = local.runner_log_options } }),
  ])
  dynamic "volume" {
    for_each = local.ca_volumes
    content { name = volume.value.name }
  }
  tags = local.common_tags
}

resource "aws_ecs_task_definition" "proxy" {
  family                   = "${local.name_prefix}-proxy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.proxy_task_cpu
  memory                   = local.proxy_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.proxy.arn
  container_definitions = jsonencode([
    merge(local.ca_init_container, { command = ["update-ca-certificates && /app/gitpod-ec2-runner setup-ca && chmod 777 /proxy-config"], mountPoints = concat(local.ca_init_mounts, [{ sourceVolume = "proxy-config", containerPath = "/proxy-config", readOnly = false }]), logConfiguration = { logDriver = "awslogs", options = local.proxy_log_options } }),
    merge(local.proxy_container, { logConfiguration = { logDriver = "awslogs", options = local.proxy_log_options } }),
  ])
  dynamic "volume" {
    for_each = concat(local.ca_volumes, [{ name = "proxy-config" }])
    content { name = volume.value.name }
  }
  tags = local.common_tags
}

resource "aws_ecs_task_definition" "adot" {
  family                   = "${local.name_prefix}-adot"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.adot.arn
  container_definitions = jsonencode([
    merge(local.ca_init_container, { logConfiguration = { logDriver = "awslogs", options = local.adot_log_options } }),
    merge(local.adot_container, { logConfiguration = { logDriver = "awslogs", options = local.adot_log_options } }),
    merge(local.metrics_audit_sync_container, { logConfiguration = { logDriver = "awslogs", options = merge(local.adot_log_options, { awslogs-stream-prefix = "metrics-audit-sync" }) } }),
  ])
  volume { name = "adot-tmp" }
  dynamic "volume" {
    for_each = concat(local.ca_volumes, [{ name = "audit" }, { name = "audit-tmp" }])
    content { name = volume.value.name }
  }
  tags = local.common_tags
}

resource "aws_ecs_service" "runner" {
  name                               = "${local.name_prefix}-runner"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.runner.arn
  desired_count                      = local.runner_is_large ? 2 : 1
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  enable_execute_command             = false
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = local.task_network_configuration.subnets
    security_groups  = local.task_network_configuration.security_groups
    assign_public_ip = local.task_network_configuration.assign_public_ip
  }
  service_connect_configuration {
    enabled = true
    service {
      port_name = "runner-api"
      client_alias {
        dns_name = "runner"
        port     = 8081
      }
    }
    service {
      port_name = "portspec"
      client_alias {
        dns_name = "runner-portspec"
        port     = 7070
      }
    }
  }
  depends_on = [
    aws_ssm_parameter.runner_config,
    aws_ssm_parameter.redis_connection,
  ]
  lifecycle { ignore_changes = [task_definition] }
  tags = local.common_tags
}

resource "aws_ecs_service" "proxy" {
  name                               = "${local.name_prefix}-proxy"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.proxy.arn
  desired_count                      = 2
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  enable_execute_command             = false
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = local.task_network_configuration.subnets
    security_groups  = local.task_network_configuration.security_groups
    assign_public_ip = local.task_network_configuration.assign_public_ip
  }
  service_connect_configuration { enabled = true }
  load_balancer {
    target_group_arn = aws_lb_target_group.proxy.arn
    container_name   = "proxy"
    container_port   = 8443
  }
  depends_on = [
    aws_ecs_service.runner,
    aws_lb_listener.proxy_tls,
    aws_ssm_parameter.runner_config,
    aws_ssm_parameter.redis_connection,
  ]
  lifecycle { ignore_changes = [task_definition] }
  tags = local.common_tags
}

resource "aws_ecs_service" "adot" {
  name                               = "${local.name_prefix}-adot"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.adot.arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  enable_execute_command             = false
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = local.task_network_configuration.subnets
    security_groups  = local.task_network_configuration.security_groups
    assign_public_ip = local.task_network_configuration.assign_public_ip
  }
  service_connect_configuration { enabled = true }
  depends_on = [aws_ecs_service.runner, aws_ssm_parameter.adot_config]
  tags       = local.common_tags
}

resource "aws_appautoscaling_target" "runner" {
  max_capacity       = local.runner_is_large ? 16 : 8
  min_capacity       = local.runner_is_large ? 2 : 1
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.runner.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "proxy" {
  max_capacity       = local.runner_is_large ? 16 : 8
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.proxy.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "runner_cpu" {
  name               = "${local.name_prefix}-runner-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.runner.resource_id
  scalable_dimension = aws_appautoscaling_target.runner.scalable_dimension
  service_namespace  = aws_appautoscaling_target.runner.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "runner_memory" {
  name               = "${local.name_prefix}-runner-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.runner.resource_id
  scalable_dimension = aws_appautoscaling_target.runner.scalable_dimension
  service_namespace  = aws_appautoscaling_target.runner.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "runner_queue_depth" {
  name               = "${local.name_prefix}-runner-queue-depth"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.runner.resource_id
  scalable_dimension = aws_appautoscaling_target.runner.scalable_dimension
  service_namespace  = aws_appautoscaling_target.runner.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 100
    scale_in_cooldown  = 300
    scale_out_cooldown = 120
    customized_metric_specification {
      metric_name = "EnvironmentQueueDepth"
      namespace   = "Ona/Runner"
      statistic   = "Average"
      dimensions {
        name  = "RunnerID"
        value = var.runner_id
      }
    }
  }
}

resource "aws_appautoscaling_policy" "proxy_cpu" {
  name               = "${local.name_prefix}-proxy-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.proxy.resource_id
  scalable_dimension = aws_appautoscaling_target.proxy.scalable_dimension
  service_namespace  = aws_appautoscaling_target.proxy.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value = 50
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "proxy_memory" {
  name               = "${local.name_prefix}-proxy-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.proxy.resource_id
  scalable_dimension = aws_appautoscaling_target.proxy.scalable_dimension
  service_namespace  = aws_appautoscaling_target.proxy.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
