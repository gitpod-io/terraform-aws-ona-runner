resource "aws_cloudwatch_log_group" "runner" {
  name              = "/gitpod/runner/${local.name_prefix}/${var.runner_id}"
  retention_in_days = 365
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-gitpod-flex-runner"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = local.common_tags
}

locals {
  bottlerocket_user_data = <<-EOT
    [settings]
    motd = "Welcome to Gitpod ECS Runner"

    [settings.ecs]
    cluster = "${aws_ecs_cluster.this.name}"
    task-cleanup-wait = "10m"
    image-cleanup-wait = "10m"
    image-cleanup-age = "10m"
    image-cleanup-delete-per-cycle = 25

    [settings.autoscaling]
    should-wait = true

    %{if try(var.proxy_config.https_proxy, "") != ""}
    [settings.network]
    https-proxy = "${var.proxy_config.https_proxy}"
    no-proxy = ["${replace(try(var.proxy_config.no_proxy, ""), ",", "\", \"")}"]
    %{endif}
  EOT
}

resource "aws_launch_template" "ecs" {
  name_prefix            = "${local.name_prefix}-ecs-"
  image_id               = data.aws_ssm_parameter.bottlerocket_ami.value
  instance_type          = local.ecs_instance_type
  update_default_version = true
  ebs_optimized          = true
  user_data              = base64encode(local.bottlerocket_user_data)
  vpc_security_group_ids = [aws_security_group.ecs.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 2
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  block_device_mappings {
    device_name = "/dev/xvdb"

    ebs {
      volume_size           = 5
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-ecs" })
  }

  tags = local.common_tags
}

resource "aws_autoscaling_group" "ecs" {
  name                      = "${local.name_prefix}-gitpod-flex-runner-asg"
  min_size                  = 1
  max_size                  = local.autoscaling_max_size
  desired_capacity          = 1
  vpc_zone_identifier       = var.runner_subnet_ids
  health_check_type         = "EC2"
  default_cooldown          = 60
  max_instance_lifetime     = 604800
  capacity_rebalance        = true
  protect_from_scale_in     = false
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  instance_maintenance_policy {
    min_healthy_percentage = 100
    max_healthy_percentage = 200
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${local.name_prefix}-ecs" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_ecs_capacity_provider" "asg" {
  name = "${local.name_prefix}-asg"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      instance_warmup_period    = 60
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.asg.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.asg.name
    weight            = 1
  }
}

locals {
  runner_environment = concat([
    { name = "AWS_REGION", value = data.aws_region.current.name },
    { name = "GITPOD_PRIVATE_ECR_PREFIX", value = "__GITPOD_PRIVATE_ECR_PREFIX__" },
    { name = "PORT_AUTHENTICATION_ENABLED", value = "true" },
    { name = "REDIS_CLUSTER_MODE", value = var.cache_engine == "MemoryDB" ? "true" : "false" },
    { name = "S3_ACCESS_ROLE_ARN", value = aws_iam_role.s3_access.arn },
    ], var.custom_ca_trust_bundle == "" ? [] : [
    { name = "GITPOD_CUSTOM_CA_BUNDLE", value = var.custom_ca_trust_bundle }
    ], var.development_version == "" ? [] : [
    { name = "GITPOD_DEVELOPMENT_VERSION", value = var.development_version }
    ], [for item in local.proxy_env : {
      name  = split("=", item)[0]
      value = join("=", slice(split("=", item), 1, length(split("=", item))))
  }])

  proxy_environment = concat([
    { name = "AWS_REGION", value = data.aws_region.current.name },
    { name = "PORT_AUTHENTICATION_ENABLED", value = "true" },
    ], [for item in local.proxy_env : {
      name  = split("=", item)[0]
      value = join("=", slice(split("=", item), 1, length(split("=", item))))
  }])

  node_exporter_job = <<-EOT
      - job_name: 'node_exporter'
        static_configs:
          - targets: ['node-exporter:9100']
            labels:
              instance: $HOSTNAME
  EOT

  prometheus_default_config = <<-EOT
    global:
      scrape_interval: 15s
      scrape_timeout: 10s
      external_labels:
        stack: ${local.name_prefix}
        account_id: ${data.aws_caller_identity.current.account_id}
        region: ${data.aws_region.current.name}

    scrape_configs:
      - job_name: 'ec2_runner'
        static_configs:
          - targets: ['ec2-runner:9090']
            labels:
              instance: $HOSTNAME
              __address__: ec2-runner:9090
      - job_name: 'ec2_runner_proxy'
        static_configs:
          - targets: ['proxy:9090']
            labels:
              instance: $HOSTNAME
              __address__: proxy:9090
    ${local.node_exporter_job}
  EOT

  prometheus_remote_write_config = <<-EOT
    ${local.prometheus_default_config}
    remote_write:
    - url: "$PROMETHEUS_URL"
      basic_auth:
        username: "$PROMETHEUS_USER"
        password: "$PROMETHEUS_PASSWORD"
  EOT

  prometheus_startup_script = <<-EOT
    #!/bin/sh
    set -euo pipefail
    echo "Configuring Prometheus"

    HOSTNAME=$(hostname)

    if [ "$ENABLE_METRICS" = "true" ]; then
      echo "$PROMETHEUS_REMOTE_WRITE_CONFIG" | sed \
        -e "s|\\$PROMETHEUS_URL|$PROMETHEUS_URL|g" \
        -e "s|\\$PROMETHEUS_USER|$PROMETHEUS_USER|g" \
        -e "s|\\$PROMETHEUS_PASSWORD|$PROMETHEUS_PASSWORD|g" \
        -e "s|\\$HOSTNAME|$HOSTNAME|g" \
        >/etc/prometheus/prometheus.yml
    else
      echo "$PROMETHEUS_DEFAULT_CONFIG" | sed \
        -e "s|\\$HOSTNAME|$HOSTNAME|g" \
        >/etc/prometheus/prometheus.yml
    fi

    echo "Starting Prometheus"
    /bin/prometheus --web.listen-address=:9093 \
      --config.file=/etc/prometheus/prometheus.yml \
      --storage.tsdb.path=/prometheus \
      --storage.tsdb.retention.time=15m \
      --storage.tsdb.retention.size=100MB \
      --web.console.libraries=/usr/share/prometheus/console_libraries \
      --web.console.templates=/usr/share/prometheus/consoles \
      --web.enable-remote-write-receiver \
      --enable-feature=remote-write-receiver
  EOT

  ca_init_container = var.custom_ca_trust_bundle == "" ? [] : [{
    name                   = "ca-trust-init"
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
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-region        = data.aws_region.current.name
        awslogs-group         = aws_cloudwatch_log_group.runner.name
        awslogs-stream-prefix = "/gitpod/ca-init/${local.name_prefix}"
      }
    }
    mountPoints = [
      { sourceVolume = "ca-certificates", containerPath = "/shared-ca-certs", readOnly = false },
      { sourceVolume = "ca-init-tmp", containerPath = "/tmp", readOnly = false },
      { sourceVolume = "ca-init-ssl-certs", containerPath = "/etc/ssl/certs", readOnly = false },
      { sourceVolume = "ca-init-usr-local", containerPath = "/usr/local/share/ca-certificates", readOnly = false },
    ]
  }]

  ca_mounts = var.custom_ca_trust_bundle == "" ? [] : [{
    sourceVolume  = "ca-certificates"
    containerPath = "/etc/ssl/certs"
    readOnly      = true
  }]

  ca_depends_on = var.custom_ca_trust_bundle == "" ? [] : [{
    containerName = "ca-trust-init"
    condition     = "SUCCESS"
  }]

  core_container_definitions = [
    {
      name                   = "ec2-runner"
      image                  = var.runner_image
      essential              = true
      memoryReservation      = local.runner_memory_reservation
      readonlyRootFilesystem = true
      command = [
        "daemon",
        "--ssm-key=${local.runner_config_key}",
        "--runner-token-secret=${local.runner_token_secret_name}",
        "--old-runner-token-secret=${data.aws_region.current.name}-${local.name_prefix}-runner-token",
        "--metrics-secret-arn=${aws_secretsmanager_secret.metrics_config.arn}",
        "--enable-ai-execution-feature",
        "--ai-execution-redis-secret=${local.redis_parameter_name}",
        "--enable-llm-proxy",
        "--enable-environment-snapshots",
      ]
      environment = local.runner_environment
      mountPoints = local.ca_mounts
      dependsOn   = local.ca_depends_on
      ulimits = [{
        name      = "nofile"
        softLimit = 65535
        hardLimit = 65535
      }]
      stopTimeout = 120
      healthCheck = {
        command     = ["CMD-SHELL", "/app/gitpod-ec2-runner ping"]
        retries     = 3
        timeout     = 5
        startPeriod = 10
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = aws_cloudwatch_log_group.runner.name
          awslogs-stream-prefix = "/gitpod/runner/${local.name_prefix}"
        }
      }
      portMappings = [
        { name = "metrics", containerPort = 9090, protocol = "tcp" },
        { name = "tcp", containerPort = 80, protocol = "tcp" },
        { name = "portspec", containerPort = 7070, protocol = "tcp" },
      ]
    },
    {
      name                   = "proxy"
      image                  = var.proxy_image
      essential              = false
      memoryReservation      = 128
      readonlyRootFilesystem = true
      command = [
        "run-runner-proxy",
        "--runner-id=${var.runner_id}",
        "--public-domain=${var.runner_domain}",
        "--cert-dir=/app/certs",
        "--management-plane-api-url=${var.api_endpoint}",
      ]
      environment = local.proxy_environment
      links       = ["ec2-runner"]
      mountPoints = concat([{
        sourceVolume  = "proxy-config"
        containerPath = "/app/certs/"
        readOnly      = false
      }], local.ca_mounts)
      dependsOn = local.ca_depends_on
      ulimits = [{
        name      = "nofile"
        softLimit = 65535
        hardLimit = 65535
      }]
      stopTimeout = 120
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f -k http://localhost:5000/_health || exit 1"]
        retries     = 3
        timeout     = 5
        startPeriod = 10
        interval    = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = aws_cloudwatch_log_group.runner.name
          awslogs-stream-prefix = "/gitpod/runner-proxy/${local.name_prefix}"
        }
      }
      portMappings = [
        { name = "proxy-metrics", containerPort = 9090, protocol = "tcp" },
        { name = "http", containerPort = 80, protocol = "tcp" },
        { name = "https", containerPort = 443, protocol = "tcp" },
        { name = "health", containerPort = 5000, protocol = "tcp" },
      ]
    },
    {
      name                   = "node-exporter"
      image                  = var.node_exporter_image
      essential              = false
      memoryReservation      = 64
      readonlyRootFilesystem = true
      command = [
        "--path.procfs=/host/proc",
        "--path.sysfs=/host/sys",
        "--path.rootfs=/host/rootfs",
        "--web.listen-address=:9100",
        "--collector.disable-defaults",
        "--collector.filesystem",
        "--collector.diskstats",
        "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)",
      ]
      environment = local.proxy_environment
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = aws_cloudwatch_log_group.runner.name
          awslogs-stream-prefix = "/gitpod/node-exporter/${local.name_prefix}"
        }
      }
      mountPoints = [
        { sourceVolume = "host-proc", containerPath = "/host/proc", readOnly = true },
        { sourceVolume = "host-sys", containerPath = "/host/sys", readOnly = true },
        { sourceVolume = "host-rootfs", containerPath = "/host/rootfs", readOnly = true },
      ]
      portMappings = [{ name = "node-exporter", containerPort = 9100, protocol = "tcp" }]
    },
    {
      name                   = "prometheus"
      image                  = var.prometheus_image
      essential              = false
      memoryReservation      = 256
      readonlyRootFilesystem = true
      links                  = ["ec2-runner", "proxy", "node-exporter"]
      entryPoint             = ["sh", "-c"]
      command                = [local.prometheus_startup_script]
      environment = concat(local.proxy_environment, [
        { name = "PROMETHEUS_DEFAULT_CONFIG", value = local.prometheus_default_config },
        { name = "PROMETHEUS_REMOTE_WRITE_CONFIG", value = local.prometheus_remote_write_config },
        { name = "RESTART", value = "true" },
      ])
      secrets = [
        { name = "ENABLE_METRICS", valueFrom = "${aws_secretsmanager_secret.metrics_config.arn}:enableMetrics::" },
        { name = "PROMETHEUS_URL", valueFrom = "${aws_secretsmanager_secret.metrics_config.arn}:url::" },
        { name = "PROMETHEUS_USER", valueFrom = "${aws_secretsmanager_secret.metrics_config.arn}:user::" },
        { name = "PROMETHEUS_PASSWORD", valueFrom = "${aws_secretsmanager_secret.metrics_config.arn}:password::" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = aws_cloudwatch_log_group.runner.name
          awslogs-stream-prefix = "/gitpod/runner/${local.name_prefix}"
        }
      }
      mountPoints = [{
        sourceVolume  = "tmp"
        containerPath = "/config"
        readOnly      = false
        }, {
        sourceVolume  = "prometheus-config"
        containerPath = "/etc/prometheus"
        readOnly      = false
      }]
    },
  ]

  container_definitions = concat(local.ca_init_container, local.core_container_definitions)
}

resource "aws_ecs_task_definition" "runner" {
  family                   = "${local.name_prefix}-runner"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  task_role_arn            = aws_iam_role.ecs_task.arn
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  container_definitions    = jsonencode(local.container_definitions)

  volume {
    name = "proxy-config"
  }

  volume {
    name = "ca-certificates"
  }

  volume {
    name = "ca-init-tmp"
  }

  volume {
    name = "ca-init-ssl-certs"
  }

  volume {
    name = "ca-init-usr-local"
  }

  volume {
    name      = "host-proc"
    host_path = "/proc"
  }

  volume {
    name      = "host-sys"
    host_path = "/sys"
  }

  volume {
    name      = "host-rootfs"
    host_path = "/"
  }

  volume {
    name = "tmp"
  }

  volume {
    name = "prometheus-config"
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "runner" {
  name                               = "${local.name_prefix}-runner"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.runner.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  enable_execute_command             = false

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.asg.name
    weight            = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.proxy.arn
    container_name   = "proxy"
    container_port   = 443
  }

  depends_on = [
    aws_ecs_cluster_capacity_providers.this,
    aws_ssm_parameter.runner_config,
    aws_ssm_parameter.redis_connection,
    aws_lb_listener.proxy_tls,
  ]

  tags = local.common_tags
}
