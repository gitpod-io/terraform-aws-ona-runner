locals {
  runner_control_function_name = substr("${local.name_prefix}-runner-control", 0, 64)
  runner_control_targets = concat([
    {
      kind                   = "runner"
      service                = aws_ecs_service.runner.name
      family                 = aws_ecs_task_definition.runner.family
      taskRoleArn            = try(one(aws_iam_role.confined_runner).arn, "disabled")
      executionRoleArn       = aws_iam_role.ecs_execution.arn
      images                 = { "ec2-runner" = "image_digest", "init-container" = "image_digest" }
      baselineTaskDefinition = try(one(aws_ecs_task_definition.confined_runner_baseline).arn, "")
    },
    {
      kind                   = "adot"
      service                = aws_ecs_service.adot.name
      family                 = ""
      taskRoleArn            = ""
      executionRoleArn       = ""
      images                 = {}
      baselineTaskDefinition = ""
    },
    ], var.restrict_ingress ? [] : [
    {
      kind                   = "proxy"
      service                = one(aws_ecs_service.proxy).name
      family                 = one(aws_ecs_task_definition.proxy).family
      taskRoleArn            = one(aws_iam_role.proxy).arn
      executionRoleArn       = aws_iam_role.ecs_execution.arn
      images                 = { proxy = "proxy_image_digest", "init-container" = "image_digest" }
      baselineTaskDefinition = one(aws_ecs_task_definition.proxy).arn
    },
  ])
  runner_control_environment = {
    CLUSTER            = aws_ecs_cluster.this.name
    PRIVATE_ECR_PREFIX = local.private_ecr_prefix
    RELEASES_URL       = local.runner_releases_base_url
    TARGETS            = jsonencode(local.runner_control_targets)
    RUNNER_ID          = var.runner_id
    INSTANCE_PROFILE   = aws_iam_instance_profile.environment.name
    APPROVED_IMAGE_IDS = local.runner_control_approved_image_ids
    SECURITY_GROUP_IDS = aws_security_group.environment.id
    SUBNET_IDS         = join(",", var.runner_subnet_ids)
  }
}

data "aws_iam_policy_document" "runner_control_assume" {
  count = local.runner_iam_managed ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "runner_control" {
  count = local.runner_iam_managed ? 1 : 0

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.runner_control_function_name}:*"]
  }

  statement {
    sid     = "UpdateOwnedServices"
    actions = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = concat([
      "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.runner.name}",
      "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.adot.name}",
      ], var.restrict_ingress ? [] : [
      "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${one(aws_ecs_service.proxy).name}",
    ])
  }

  statement {
    sid     = "RegisterOwnedTaskDefinitions"
    actions = ["ecs:RegisterTaskDefinition", "ecs:TagResource"]
    resources = concat(
      ["arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/${aws_ecs_task_definition.runner.family}:*"],
      var.restrict_ingress ? [] : ["arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/${one(aws_ecs_task_definition.proxy).family}:*"],
    )
  }


  statement {
    sid       = "DescribeTaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "PassFixedTaskRoles"
    actions   = ["iam:PassRole"]
    resources = concat([one(aws_iam_role.confined_runner).arn, aws_iam_role.ecs_execution.arn], aws_iam_role.proxy[*].arn)
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "PassEnvironmentRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.environment.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid = "ValidateAndCreateOwnedCompute"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "ec2:CreateLaunchTemplate", "ec2:CreateLaunchTemplateVersion", "ec2:CreateNetworkInterface",
      "ec2:CreateSnapshot", "ec2:CreateVolume", "ec2:DescribeImages", "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstances", "ec2:DescribeLaunchTemplates", "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeSnapshots", "ec2:DescribeVolumes", "ec2:RegisterImage", "ec2:RunInstances",
      "ssm:GetCommandInvocation", "ssm:ListCommands", "ssm:SendCommand",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "TagOwnedComputeDuringCreation"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateLaunchTemplate", "CreateSnapshot", "CreateVolume", "RegisterImage", "RunInstances"]
    }
  }

  statement {
    sid       = "MutateOwnedWarmPoolLaunch"
    actions   = ["autoscaling:CreateAutoScalingGroup", "autoscaling:StartInstanceRefresh", "autoscaling:UpdateAutoScalingGroup"]
    resources = ["arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/ona-wp-${var.runner_id}-*"]
  }
}

resource "aws_iam_policy" "runner_control_boundary" {
  count       = local.runner_iam_managed ? 1 : 0
  name_prefix = "${local.iam_role_name_prefix}-control-boundary-"
  description = "Permission boundary for the versioned Ona runner control function"
  policy      = one(data.aws_iam_policy_document.runner_control).json
  tags        = local.common_tags
}

resource "aws_iam_role" "runner_control" {
  count                = local.runner_iam_managed ? 1 : 0
  name_prefix          = "${local.iam_role_name_prefix}-control-"
  assume_role_policy   = one(data.aws_iam_policy_document.runner_control_assume).json
  permissions_boundary = one(aws_iam_policy.runner_control_boundary).arn
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "runner_control" {
  count  = local.runner_iam_managed ? 1 : 0
  role   = one(aws_iam_role.runner_control).id
  policy = one(data.aws_iam_policy_document.runner_control).json
}

resource "aws_lambda_function" "runner_control" {
  count = local.runner_iam_managed ? 1 : 0

  function_name    = local.runner_control_function_name
  role             = one(aws_iam_role.runner_control).arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = one(data.archive_file.runner_control).output_path
  source_code_hash = one(data.archive_file.runner_control).output_base64sha256
  timeout          = 30

  environment {
    variables = local.runner_control_environment
  }

  tags = local.common_tags
}
