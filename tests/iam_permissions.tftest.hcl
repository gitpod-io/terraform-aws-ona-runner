# Validate policy statements with the real AWS provider and local account/task
# role fixtures. No AWS resources are applied.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_resource {
  target          = aws_secretsmanager_secret.external_credential_issuer[0]
  override_during = plan
  values          = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:client-issuer-123456" }
}

override_resource {
  target          = aws_secretsmanager_secret.external_credential_proxy[0]
  override_during = plan
  values          = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:proxy-material-123456" }
}

run "external_credential_role_separation" {
  command = plan
  variables { enable_external_credential_proxy = true }
  assert {
    condition = length(data.aws_iam_policy_document.external_credentials[0].statement) == 2 && alltrue([
      for statement in data.aws_iam_policy_document.external_credentials[0].statement :
      (statement.sid == "ReadProxyMaterial" && statement.actions == toset(["secretsmanager:GetSecretValue"]) && statement.resources == toset(["arn:aws:secretsmanager:us-east-1:123456789012:secret:proxy-material-123456"])) ||
      (statement.sid == "ReadCustomTrustBundle" && statement.actions == toset(["s3:GetObject"]) && statement.resources == toset(["arn:aws:s3:::gitpod-*/*"]))
    ])
    error_message = "The proxy may read its TLS material and custom CA, never the client signing key or runner token."
  }
  assert {
    condition     = anytrue([for statement in data.aws_iam_policy_document.ecs_task.statement : statement.sid == "ManageExternalCredentialMaterial" && contains(statement.actions, "secretsmanager:PutSecretValue") && contains(statement.resources, "arn:aws:secretsmanager:us-east-1:123456789012:secret:client-issuer-123456") && contains(statement.resources, "arn:aws:secretsmanager:us-east-1:123456789012:secret:proxy-material-123456")])
    error_message = "The runner must own initialization of both separate TLS resources."
  }
}

override_data {
  override_during = plan
  target          = data.aws_caller_identity.current
  values          = { account_id = "123456789012" }
}

override_data {
  override_during = plan
  target          = data.aws_region.current
  values          = { name = "us-east-1" }
}

variables {
  runner_id                = "019d6999-807b-7e52-ab6f-c9202f13ecf2"
  runner_token             = "test-token"
  runner_domain            = "runner.example.com"
  certificate_arn          = "arn:aws:acm:us-east-1:123456789012:certificate/test"
  vpc_id                   = "vpc-00000000000000000"
  runner_subnet_ids        = ["subnet-00000000000000000"]
  load_balancer_subnet_ids = ["subnet-00000000000000000"]
}

override_resource {
  target          = aws_iam_role.ecs_task
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:role/test-runner"
    id  = "test-runner"
  }
}

override_resource {
  target          = aws_iam_role.ecs_execution
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/test-execution" }
}

override_resource {
  target          = aws_iam_role.proxy
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/test-proxy" }
}

override_resource {
  target          = aws_s3_bucket.container_registry
  override_during = plan
  values          = { arn = "arn:aws:s3:::test-registry" }
}

run "warm_pool_runtime_permissions" {
  command = plan

  assert {
    condition = alltrue([
      for action in [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DetachInstances",
        "autoscaling:PutScalingPolicy",
        "autoscaling:DescribePolicies",
        "autoscaling:DeletePolicy",
        "autoscaling:DeleteWarmPool",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:StartInstanceRefresh",
        "ec2:CreateLaunchTemplate",
        "ec2:CreateLaunchTemplateVersion",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeLaunchTemplateVersions",
        "cloudwatch:PutMetricData",
        ] : anytrue([
          for statement in data.aws_iam_policy_document.ecs_task.statement :
          coalesce(statement.effect, "Allow") == "Allow" &&
          contains(statement.actions, action)
      ])
    ])
    error_message = "The runner task role must allow all ASG warm-pool runtime actions."
  }

  assert {
    condition = anytrue([
      for statement in data.aws_iam_policy_document.ecs_task.statement :
      coalesce(statement.effect, "Allow") == "Allow" &&
      contains(statement.actions, "autoscaling:DescribeAutoScalingGroups") &&
      contains(statement.resources, "*")
    ])
    error_message = "DescribeAutoScalingGroups requires resource *; an ASG ARN does not authorize this read."
  }

  assert {
    condition = (
      aws_iam_role_policy.ecs_task.role == aws_iam_role.ecs_task.id &&
      aws_ecs_task_definition.runner.task_role_arn == aws_iam_role.ecs_task.arn
    )
    error_message = "Warm-pool permissions must be attached to the role used by the runner task."
  }
}

run "runner_operation_scopes" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in data.aws_iam_policy_document.ecs_task.statement : [
        for action in statement.actions : !strcontains(action, "*")
      ]
    ]))
    error_message = "Runner action grants must remain explicit so resource-scope assertions cannot be bypassed by a wildcard action."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.ecs_task.statement :
      statement.resources == toset(["arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:*:autoScalingGroupName/ona-wp-*"])
      if anytrue([for action in statement.actions : startswith(action, "autoscaling:") && !startswith(action, "autoscaling:Describe")])
    ])
    error_message = "ASG mutations must only target warm-pool groups in this account and region."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.ecs_task.statement :
      statement.resources == toset(["arn:aws:ec2:us-east-1:123456789012:launch-template/*"])
      if contains(statement.actions, "ec2:CreateLaunchTemplateVersion") || contains(statement.actions, "ec2:DeleteLaunchTemplate")
    ])
    error_message = "Existing launch-template mutations must remain account/region scoped, including duplicate grants."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.ecs_task.statement :
      statement.resources == toset(["*"]) && length(statement.condition) == 1 &&
      one(statement.condition).test == "StringLike" &&
      one(statement.condition).variable == "cloudwatch:namespace" &&
      one(statement.condition).values == tolist(["Ona/*"])
      if contains(statement.actions, "cloudwatch:PutMetricData")
    ])
    error_message = "Every metric publication grant must require an Ona namespace."
  }

  assert {
    condition = alltrue([
      for action in ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:SendCommand"] : anytrue([
        for statement in data.aws_iam_policy_document.ecs_task.statement :
        coalesce(statement.effect, "Allow") == "Allow" && contains(statement.actions, action)
      ])
    ])
    error_message = "Runner configuration, environment parameters, and shell commands must retain their runtime grants."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.ecs_task.statement :
      statement.resources == toset(["arn:aws:ssm:us-east-1:123456789012:parameter/gitpod/runner/*"])
      if anytrue([for action in statement.actions : contains(["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:PutParameter", "ssm:DeleteParameter"], action)]) && statement.sid != "ReadRunnerSecretsAndConfig"
    ])
    error_message = "Runner parameter operations must remain under the runner SSM path."
  }

  assert {
    condition = alltrue([
      for action in ["ssm:DescribeParameters", "ssm:GetCommandInvocation"] : anytrue([
        for statement in data.aws_iam_policy_document.ecs_task.statement :
        contains(statement.actions, action) && statement.resources == toset(["*"]) && length(statement.condition) == 0
      ])
    ])
    error_message = "SSM status and discovery APIs need unconditional wildcard-resource grants."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.ecs_task.statement : statement.resources == toset([
        "arn:aws:ec2:us-east-1:123456789012:instance/*",
        "arn:aws:ssm:*:*:document/AWS-RunShellScript",
      ]) if contains(statement.actions, "ssm:SendCommand")
    ])
    error_message = "SSM commands need both the instance target and the supported shell document, not arbitrary documents."
  }
}

run "ecs_update_role_passing" {
  command = plan

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.ecs_task.statement :
      coalesce(statement.effect, "Allow") == "Allow" && statement.resources == toset([
        "arn:aws:iam::123456789012:role/test-execution",
        "arn:aws:iam::123456789012:role/test-runner",
        "arn:aws:iam::123456789012:role/test-proxy",
      ]) && length(statement.condition) == 1 &&
      one(statement.condition).test == "StringEquals" &&
      one(statement.condition).variable == "iam:PassedToService" &&
      one(statement.condition).values == tolist(["ecs-tasks.amazonaws.com"])
      if contains(statement.actions, "iam:PassRole") && statement.sid != "PassEnvironmentRole"
    ]) && anytrue([for statement in data.aws_iam_policy_document.ecs_task.statement : statement.sid == "PassECSTaskRoles"])
    error_message = "Runtime updates must pass only the runner/proxy task roles and execution role, and only to ECS."
  }
}

run "restricted_ecs_update_role_passing" {
  command = plan
  variables {
    restrict_ingress = true
  }

  assert {
    condition = one([
      for statement in data.aws_iam_policy_document.ecs_task.statement : statement.resources
      if statement.sid == "PassECSTaskRoles"
      ]) == toset([
      "arn:aws:iam::123456789012:role/test-execution",
      "arn:aws:iam::123456789012:role/test-runner",
    ])
    error_message = "Restricted runners must plan without a proxy role and must not pass one to ECS."
  }
}

run "cache_session_contract" {
  command = plan

  assert {
    condition = try(
      length(data.aws_iam_policy_document.s3_access_assume.statement) == 1 &&
      coalesce(one(data.aws_iam_policy_document.s3_access_assume.statement).effect, "Allow") == "Allow" &&
      one(data.aws_iam_policy_document.s3_access_assume.statement).actions == toset(["sts:AssumeRole", "sts:TagSession"]) &&
      length(one(data.aws_iam_policy_document.s3_access_assume.statement).principals) == 1 &&
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).type == "AWS" &&
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).identifiers == toset(["arn:aws:iam::123456789012:role/test-runner"]) &&
      length(one(data.aws_iam_policy_document.s3_access_assume.statement).condition) == 2 &&
      alltrue([
        for condition in one(data.aws_iam_policy_document.s3_access_assume.statement).condition :
        (condition.test == "StringLike" && condition.variable == "aws:RequestTag/gitpod.dev/environment-creator-id" && condition.values == tolist(["?*"])) ||
        (condition.test == "ForAllValues:StringEquals" && condition.variable == "aws:TagKeys" && condition.values == tolist(["gitpod.dev/environment-creator-id"]))
      ]), false
    )
    error_message = "Cache sessions must be issued by the runner with a nonempty creator tag and no other session tags."
  }

  assert {
    condition = (
      length(data.aws_iam_policy_document.s3_access.statement) == 4 &&
      length([for statement in data.aws_iam_policy_document.s3_access.statement : statement if statement.effect == "Deny"]) == 1 &&
      alltrue([
        for statement in data.aws_iam_policy_document.s3_access.statement :
        statement.actions == toset(["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"]) &&
        statement.resources == toset(["arn:aws:s3:::test-registry/$${aws:PrincipalTag/gitpod.dev/environment-creator-id}/*"]) &&
        length(statement.condition) == 0
        if coalesce(statement.effect, "Allow") == "Allow" && statement.actions != toset(["s3:ListBucket"]) && statement.actions != toset(["s3:GetBucketLocation"])
      ]) &&
      anytrue([
        for statement in data.aws_iam_policy_document.s3_access.statement :
        coalesce(statement.effect, "Allow") == "Allow" && contains(statement.actions, "s3:PutObject")
      ])
    )
    error_message = "Cache object access must cover exactly the supported operations within the session creator's prefix."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.s3_access.statement :
      statement.actions == toset(["s3:ListBucket"]) && statement.resources == toset(["arn:aws:s3:::test-registry"]) &&
      length(statement.condition) == 1 && one(statement.condition).test == "StringNotLike" &&
      one(statement.condition).variable == "s3:prefix" &&
      one(statement.condition).values == tolist(["$${aws:PrincipalTag/gitpod.dev/environment-creator-id}/*"])
      if statement.effect == "Deny"
    ])
    error_message = "Cache listing must explicitly deny prefixes outside the session creator's directory."
  }

  assert {
    condition = alltrue([
      for action in ["s3:ListBucket", "s3:GetBucketLocation"] : anytrue([
        for statement in data.aws_iam_policy_document.s3_access.statement :
        coalesce(statement.effect, "Allow") == "Allow" && statement.actions == toset([action]) &&
        statement.resources == toset(["arn:aws:s3:::test-registry"]) && length(statement.condition) == 0
      ])
    ])
    error_message = "Cache clients need bucket location and listing grants; the separate deny enforces listing prefixes."
  }
}

run "task_ca_and_environment_contracts" {
  command = plan

  assert {
    condition = alltrue([
      for statements in [data.aws_iam_policy_document.ecs_task.statement, data.aws_iam_policy_document.proxy.statement, data.aws_iam_policy_document.adot.statement] : anytrue([
        for statement in statements :
        coalesce(statement.effect, "Allow") == "Allow" && statement.actions == toset(["s3:GetObject"]) &&
        statement.resources == toset(["arn:aws:s3:::gitpod-*/*"]) && length(statement.condition) == 0
      ])
    ])
    error_message = "Every task running setup-ca must be able to read supported S3 CA bundles."
  }

  assert {
    condition = try(
      one(data.aws_iam_policy_document.ec2_assume_role.statement).actions == toset(["sts:AssumeRole"]) &&
      one(one(data.aws_iam_policy_document.ec2_assume_role.statement).principals).identifiers == toset(["ec2.amazonaws.com"]) &&
      one(one(data.aws_iam_policy_document.ec2_assume_role.statement).condition).test == "ArnLike" &&
      one(one(data.aws_iam_policy_document.ec2_assume_role.statement).condition).variable == "aws:SourceArn" &&
      one(one(data.aws_iam_policy_document.ec2_assume_role.statement).condition).values == tolist(["arn:aws:ec2:us-east-1:123456789012:instance/*"]), false
    )
    error_message = "Environment role trust must remain bound to this account's regional EC2 instances."
  }

  assert {
    condition = alltrue(flatten([
      for statement in data.aws_iam_policy_document.environment.statement : [
        for action in statement.actions : !startswith(action, "logs:") && action != "*"
      ]
    ])) && anytrue([for statement in data.aws_iam_policy_document.environment.statement : statement.sid == "AllowWriteOwnLogs"])
    error_message = "Environment logging uses its own S3 prefix, without unused CloudWatch Logs grants."
  }
}
