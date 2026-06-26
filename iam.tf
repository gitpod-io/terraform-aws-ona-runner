data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name_prefix        = "${local.name_prefix}-ecs-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution" {
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution.json
}

data "aws_iam_policy_document" "ecs_execution" {
  statement {
    sid       = "PrometheusMetricsSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.metrics_config.arn]
  }

  statement {
    sid       = "PullThroughCache"
    actions   = ["ecr:BatchImportUpstreamImage"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "ecs_task" {
  name_prefix        = "${local.name_prefix}-ecs-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task" {
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task.json
}

data "aws_iam_policy_document" "ecs_task" {
  statement {
    sid = "ReadRunnerSecretsAndConfig"
    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      aws_secretsmanager_secret.runner_token.arn,
      aws_secretsmanager_secret.metrics_config.arn,
      aws_ssm_parameter.runner_config.arn,
      aws_ssm_parameter.redis_connection.arn,
    ]
  }

  statement {
    sid = "DynamoResourcesTable"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:PartiQLSelect",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:Scan",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.resources.arn]
  }

  statement {
    sid       = "AssumeRunnerManagedRoles"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.s3_access.arn, aws_iam_role.devcontainer_cache_registry_access.arn]
  }

  statement {
    sid = "AgentAndLogsBuckets"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = [
      aws_s3_bucket.agent.arn,
      "${aws_s3_bucket.agent.arn}/*",
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]
  }

  statement {
    sid = "DevcontainerCacheRegistryManagement"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:DeleteRepository",
      "ecr:PutLifecyclePolicy",
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      "ecr:SetRepositoryPolicy",
      "ecr:TagResource",
      "ecr:ListTagsForResource",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:GetLifecyclePolicyPreview",
      "ecr:GetRegistryScanningConfiguration",
      "ecr:GetImageScanningConfiguration",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/gitpod-runner-${var.runner_id}/*"]
  }

  statement {
    sid       = "BedrockInvocation"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["arn:aws:bedrock:${split("-", data.aws_region.current.name)[0]}::*"]
  }

  statement {
    sid = "ASGWarmPoolManagement"
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:DeleteLaunchTemplate",
      "ec2:DescribeLaunchTemplateVersions",
      "autoscaling:CreateAutoScalingGroup",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:DeletePolicy",
      "autoscaling:DetachInstances",
      "autoscaling:PutScalingPolicy",
      "autoscaling:PutWarmPool",
      "autoscaling:DeleteWarmPool",
      "autoscaling:StartInstanceRefresh",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:DescribePolicies",
      "autoscaling:DescribeWarmPool",
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
  }

  statement {
    sid = "EnvironmentEC2Lifecycle"
    actions = [
      "ec2:CancelSpotInstanceRequests",
      "ec2:AttachNetworkInterface",
      "ec2:AttachVolume",
      "ec2:CreateNetworkInterface",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteNetworkInterface",
      "ec2:DeleteSnapshot",
      "ec2:DeleteTags",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeNatGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcs",
      "ec2:DetachNetworkInterface",
      "ec2:DetachVolume",
      "ec2:GetConsoleOutput",
      "ec2:RegisterImage",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid = "EnvironmentSSMCommands"
    actions = [
      "ssm:DeleteParameter",
      "ssm:GetCommandInvocation",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:PutParameter",
      "ssm:SendCommand",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "SSMSendRunShellScript"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:*:*:document/AWS-RunShellScript"]
  }

  statement {
    sid = "EnvironmentSecrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:TagResource",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*${var.runner_id}*",
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*gitpod*",
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*ona*",
    ]
  }

  statement {
    sid       = "CallerIdentity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "PassEnvironmentRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.environment.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "autoscaling.amazonaws.com"]
    }
  }

  statement {
    sid = "UpdateOwnECSService"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:RegisterTaskDefinition",
      "ecs:TagResource",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:DescribeContainerInstances",
      "ecs:UpdateServicePrimaryTaskSet",
      "application-autoscaling:DescribeScalableTargets",
      "application-autoscaling:DescribeScheduledActions",
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:DeleteScalingPolicy",
      "application-autoscaling:DescribeScalingPolicies",
      "iam:GetRole",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "CreateRequiredServiceLinkedRoles"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService",
    ]
  }

  statement {
    sid       = "ReadRunnerCloudWatchLogs"
    actions   = ["logs:FilterLogEvents"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/gitpod/*"]
  }
}

resource "aws_iam_role" "ecs_instance" {
  name_prefix        = "${local.name_prefix}-ecs-instance-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecs" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs" {
  name_prefix = "${local.name_prefix}-ecs-"
  role        = aws_iam_role.ecs_instance.name
  tags        = local.common_tags
}

resource "aws_iam_role" "environment" {
  name_prefix        = "${local.name_prefix}-environment-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = merge(local.common_tags, { "gitpod.dev/environment-role" = "true" })
}

resource "aws_iam_instance_profile" "environment" {
  name_prefix = "${local.name_prefix}-environment-"
  role        = aws_iam_role.environment.name
  tags        = local.common_tags
}

resource "aws_iam_role_policy" "environment" {
  role   = aws_iam_role.environment.id
  policy = data.aws_iam_policy_document.environment.json
}

data "aws_iam_policy_document" "environment" {
  statement {
    sid       = "AllowSSMSessionManager"
    actions   = ["ssm:UpdateInstanceInformation"]
    resources = ["*"]
  }

  statement {
    sid = "AllowSSMMessages"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowEC2Messages"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowWriteOwnLogs"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/logs/environments/$${aws:userid}/*"]
  }

  statement {
    sid       = "AllowBasicLogging"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/gitpod/environments/*"]
  }

  statement {
    sid       = "AllowSelfTaggingOperational"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:SourceInstanceARN"
      values   = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/$${ec2:InstanceId}"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values = [
        "gitpod.dev/start-error-message",
        "gitpod.dev/error-code",
        "gitpod.dev/error-component",
        "gitpod.dev/stop-error-message",
      ]
    }

    condition {
      test     = "Null"
      variable = "aws:TagKeys"
      values   = ["false"]
    }
  }
}

resource "aws_iam_role" "s3_access" {
  name_prefix        = "${local.name_prefix}-s3-access-"
  assume_role_policy = data.aws_iam_policy_document.s3_access_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "s3_access_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com", "ec2.amazonaws.com"]
    }

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.environment.arn, aws_iam_role.ecs_task.arn]
    }
  }

  statement {
    actions = ["sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.environment.arn, aws_iam_role.ecs_task.arn]
    }
  }
}

resource "aws_iam_role_policy" "s3_access" {
  role   = aws_iam_role.s3_access.id
  policy = data.aws_iam_policy_document.s3_access.json
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = [aws_s3_bucket.container_registry.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "$${aws:PrincipalTag/gitpod.dev/environment-creator-id}/*",
        "$${aws:PrincipalTag/gitpod.dev/environment-creator-id}",
      ]
    }
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.container_registry.arn}/$${aws:PrincipalTag/gitpod.dev/environment-creator-id}/*"]
  }

  statement {
    actions   = ["s3:*Object", "s3:ListBucket"]
    resources = [aws_s3_bucket.container_registry.arn, "${aws_s3_bucket.container_registry.arn}/*"]
  }

  statement {
    actions   = ["sts:TagSession", "sts:AssumeRole", "sts:AssumeRoleWithWebIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "devcontainer_cache_registry_access" {
  name_prefix        = "${local.name_prefix}-ecr-cache-"
  assume_role_policy = data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "devcontainer_cache_registry_access_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ecs_task.arn]
    }
  }
}

resource "aws_iam_role_policy" "devcontainer_cache_registry_access" {
  role   = aws_iam_role.devcontainer_cache_registry_access.id
  policy = data.aws_iam_policy_document.devcontainer_cache_registry_access.json
}

data "aws_iam_policy_document" "devcontainer_cache_registry_access" {
  statement {
    sid = "AllowPullFromProject"
    actions = [
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/gitpod-runner-$${aws:PrincipalTag/gitpod.dev/runner-id}/projects/$${aws:PrincipalTag/gitpod.dev/project-id}/image-build"]
  }

  statement {
    sid = "AllowPushToProject"
    actions = [
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/gitpod-runner-$${aws:PrincipalTag/gitpod.dev/runner-id}/projects/$${aws:PrincipalTag/gitpod.dev/project-id}/image-build"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/gitpod.dev/push"
      values   = ["true"]
    }
  }

  statement {
    sid       = "AllowGetAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}
