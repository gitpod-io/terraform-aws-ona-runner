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

  statement {
    sid       = "ReadCABundles"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::gitpod-*/*"]
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
      "ec2:DeleteSnapshot", "ec2:DeleteTags", "ec2:DeleteVolume", "ec2:DeregisterImage",
      "ec2:DetachNetworkInterface", "ec2:DetachVolume", "ec2:GetConsoleOutput", "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume", "ec2:StartInstances", "ec2:StopInstances", "ec2:TerminateInstances",
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:image/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/gitpod.dev/runner-id"
      values   = [var.runner_id]
    }
  }

  statement {
    sid       = "DescribeCompute"
    actions   = ["ec2:Describe*", "autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribePolicies", "autoscaling:DescribeWarmPool", "ssm:DescribeParameters", "ssm:GetCommandInvocation"]
    resources = ["*"]
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
