data "aws_iam_policy_document" "retired_runner_assume" {
  statement {
    effect  = "Deny"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "retired_runner" {
  statement {
    sid       = "Retired"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "confined_runner_boundary" {
  count = local.runner_iam_managed ? 1 : 0

  statement {
    sid = "ExactRunnerData"
    actions = [
      "dynamodb:BatchWriteItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable", "dynamodb:GetItem",
      "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:PartiQLSelect", "dynamodb:PutItem",
      "dynamodb:Query", "dynamodb:Scan", "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.resources.arn]
  }

  statement {
    sid = "ExactRunnerSecrets"
    actions = [
      "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:TagResource",
    ]
    resources = concat(
      [local.runner_token_secret_arn, aws_secretsmanager_secret.metrics_config.arn],
      aws_secretsmanager_secret.internal_llm_tls[*].arn,
    )
  }

  statement {
    sid     = "ExactRunnerParameters"
    actions = ["ssm:DeleteParameter", "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:PutParameter"]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.runner_config_key}",
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.runner_config_key}/*",
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.redis_parameter_name}",
    ]
  }

  statement {
    sid     = "AssumeExactCacheRoles"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.iam_role_name_prefix}-s3-access-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.iam_role_name_prefix}-ecr-cache-*",
    ]
  }

  statement {
    sid = "RunnerBuckets"
    actions = [
      "s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:ListBucket",
      "s3:ListMultipartUploadParts", "s3:PutObject",
    ]
    resources = [aws_s3_bucket.agent.arn, "${aws_s3_bucket.agent.arn}/*", aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.custom_ca_s3_object_arn == "" ? [] : [var.custom_ca_s3_object_arn]

    content {
      sid       = "ReadConfiguredCABundle"
      actions   = ["s3:GetObject"]
      resources = [statement.value]
    }
  }

  statement {
    sid = "DevcontainerCacheRegistry"
    actions = [
      "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories", "ecr:GetImageScanningConfiguration",
      "ecr:GetLifecyclePolicy", "ecr:GetLifecyclePolicyPreview", "ecr:GetRegistryScanningConfiguration",
      "ecr:GetRepositoryPolicy", "ecr:ListTagsForResource", "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability", "ecr:PutLifecyclePolicy", "ecr:SetRepositoryPolicy", "ecr:TagResource",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/gitpod-runner-${var.runner_id}/*"]
  }

  statement {
    sid       = "InvokeRunnerControl"
    actions   = ["lambda:InvokeFunction"]
    resources = ["arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.runner_control_function_name}"]
  }

  statement {
    sid = "OwnedComputeMutation"
    actions = [
      "ec2:AttachNetworkInterface", "ec2:AttachVolume", "ec2:CancelSpotInstanceRequests", "ec2:DeleteNetworkInterface",
      "ec2:DeleteLaunchTemplate", "ec2:DeleteSnapshot", "ec2:DeleteVolume", "ec2:DeregisterImage",
      "ec2:DetachNetworkInterface", "ec2:DetachVolume", "ec2:GetConsoleOutput", "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume", "ec2:StartInstances", "ec2:StopInstances", "ec2:TerminateInstances",
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:image/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/gitpod.dev/runner-id"
      values   = [var.runner_id]
    }
  }

  statement {
    sid = "TagOwnedComputeMetadata"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:image/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/gitpod.dev/runner-id"
      values   = [var.runner_id]
    }
  }

  statement {
    sid       = "DenyRunnerOwnerReassignment"
    effect    = "Deny"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestTag/gitpod.dev/runner-id"
      values   = [var.runner_id]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/gitpod.dev/runner-id"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyRunnerOwnerTagDeletion"
    effect    = "Deny"
    actions   = ["ec2:DeleteTags"]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = ["gitpod.dev/runner-id"]
    }
  }

  statement {
    sid = "DescribeComputeCatalog"
    actions = [
      "ec2:DescribeInternetGateways", "ec2:DescribeInstanceStatus", "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeImages", "ec2:DescribeInstanceTypes", "ec2:DescribeNatGateways", "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeTags",
      "ec2:DescribeVpcAttribute", "ec2:DescribeVpcEndpoints", "ec2:DescribeVpcs",
      "autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribePolicies", "autoscaling:DescribeWarmPool",
      "ssm:DescribeParameters",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadEnvironmentRole"
    actions   = ["iam:GetRole"]
    resources = [aws_iam_role.environment.arn]
  }

  statement {
    sid = "OwnedWarmPoolMaintenance"
    actions = [
      "autoscaling:DeleteAutoScalingGroup", "autoscaling:DeletePolicy", "autoscaling:DeleteWarmPool",
      "autoscaling:DetachInstances", "autoscaling:PutScalingPolicy", "autoscaling:PutWarmPool",
    ]
    resources = ["arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/ona-wp-${var.runner_id}-*"]
  }

  statement {
    sid       = "PublishRunnerMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "cloudwatch:namespace"
      values   = ["Ona/*"]
    }
  }

  statement {
    sid       = "BedrockInvocation"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:inference-profile/*", "arn:aws:bedrock:*::foundation-model/*"]
  }

  statement {
    sid       = "ECRAuthorization"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "CallerIdentity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadRunnerLogs"
    actions   = ["logs:FilterLogEvents"]
    resources = [aws_cloudwatch_log_group.runner.arn]
  }

  statement {
    sid     = "CreateRequiredServiceLinkedRoles"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService",
    ]
  }
}

resource "aws_iam_policy" "confined_runner_boundary" {
  count       = local.runner_iam_managed ? 1 : 0
  name_prefix = "${local.iam_role_name_prefix}-confined-boundary-"
  description = "Permission boundary for the confined Ona runner task role"
  policy      = one(data.aws_iam_policy_document.confined_runner_boundary).json
  tags        = local.common_tags
}

resource "aws_iam_role" "confined_runner" {
  count                = local.runner_iam_managed ? 1 : 0
  name_prefix          = "${local.iam_role_name_prefix}-conf-task-"
  assume_role_policy   = data.aws_iam_policy_document.fargate_task_assume_role.json
  permissions_boundary = one(aws_iam_policy.confined_runner_boundary).arn
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "confined_runner" {
  count  = local.runner_iam_managed ? 1 : 0
  role   = one(aws_iam_role.confined_runner).id
  policy = data.aws_iam_policy_document.ecs_task.json
}

data "aws_iam_policy_document" "confined_runner_ca" {
  count = local.runner_iam_managed && var.custom_ca_s3_object_arn != "" ? 1 : 0

  statement {
    sid       = "ReadConfiguredCABundle"
    actions   = ["s3:GetObject"]
    resources = [var.custom_ca_s3_object_arn]
  }
}

resource "aws_iam_role_policy" "confined_runner_ca" {
  count  = local.runner_iam_managed && var.custom_ca_s3_object_arn != "" ? 1 : 0
  role   = one(aws_iam_role.confined_runner).id
  policy = one(data.aws_iam_policy_document.confined_runner_ca).json
}

data "aws_iam_policy_document" "confined_runner_control" {
  count = local.runner_iam_managed ? 1 : 0

  statement {
    sid       = "InvokeRunnerControl"
    actions   = ["lambda:InvokeFunction"]
    resources = [one(aws_lambda_function.runner_control).arn]
  }
}

resource "aws_iam_role_policy" "confined_runner_control" {
  count  = local.runner_iam_managed ? 1 : 0
  role   = one(aws_iam_role.confined_runner).id
  policy = one(data.aws_iam_policy_document.confined_runner_control).json
}
