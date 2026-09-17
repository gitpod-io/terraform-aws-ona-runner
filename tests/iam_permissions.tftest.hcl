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

mock_provider "http" {}
mock_provider "archive" {}

override_data {
  target = data.http.runner_release_manifest
  values = {
    response_body = <<-JSON
      {"version":"20260917.657","image_digest":"public.ecr.aws/example/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","proxy_image_digest":"public.ecr.aws/example/proxy@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runner_control_protocol":1,"runner_control_source_sha256":"sha256:61e3e54dc5206a73859ff79d1e723648214b0d6510f96b3c665f561aca60c2d6","cloudformation_template_url":"https://releases.gitpod.io/ec2/releases/20260917.657/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"}
    JSON
  }
}

override_data {
  target = data.http.runner_release_template
  values = {
    response_body = jsonencode({
      Resources = {
        Control = {
          Type = "AWS::Lambda::Function"
          Properties = {
            Handler = "index.handler"
            Code    = { ZipFile = "exports.handler = async () => ({ ok: true });" }
            Environment = { Variables = {
              APPROVED_IMAGE_IDS = "ami-00000000000000001,ami-00000000000000002"
            } }
          }
        }
      }
    })
  }
}

override_data {
  target = data.archive_file.runner_control
  values = {
    output_path         = "/tmp/runner-control.zip"
    output_base64sha256 = "YWJj"
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
  runner_id                     = "runner-a"
  runner_token                  = "test-token"
  runner_domain                 = "runner.example.com"
  certificate_arn               = "arn:aws:acm:us-east-1:123456789012:certificate/test"
  vpc_id                        = "vpc-00000000000000000"
  runner_subnet_ids             = ["subnet-00000000000000000"]
  load_balancer_subnet_ids      = ["subnet-00000000000000000"]
  runner_template_build_version = "20260917.657"
}

override_resource {
  target          = aws_iam_role.ecs_task
  override_during = plan
  values = {
    arn  = "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecs-task-fixture"
    id   = "ona-runner-51cf5b27370de-ecs-task-fixture"
    name = "ona-runner-51cf5b27370de-ecs-task-fixture"
  }
}

override_resource {
  target          = aws_iam_role.confined_runner
  override_during = plan
  values = {
    arn  = "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-conf-task-fixture"
    id   = "ona-runner-51cf5b27370de-conf-task-fixture"
    name = "ona-runner-51cf5b27370de-conf-task-fixture"
  }
}

override_resource {
  target          = aws_iam_role.runner_control
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:role/test-runner-control"
    id  = "test-runner-control"
  }
}

override_resource {
  target          = aws_ecs_task_definition.runner
  override_during = plan
  values = {
    arn    = "arn:aws:ecs:us-east-1:123456789012:task-definition/test-runner:1"
    family = "test-runner"
  }
}

override_resource {
  target          = aws_ecs_task_definition.confined_runner_baseline
  override_during = plan
  values = {
    arn    = "arn:aws:ecs:us-east-1:123456789012:task-definition/test-runner:2"
    family = "test-runner"
  }
}

override_resource {
  target          = aws_ecs_task_definition.proxy
  override_during = plan
  values = {
    arn    = "arn:aws:ecs:us-east-1:123456789012:task-definition/test-proxy:1"
    family = "test-proxy"
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
  target          = aws_iam_role.s3_access
  override_during = plan
  values = {
    arn  = "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-s3-access-fixture"
    id   = "ona-runner-51cf5b27370de-s3-access-fixture"
    name = "ona-runner-51cf5b27370de-s3-access-fixture"
  }
}

override_resource {
  target          = aws_iam_role.devcontainer_cache_registry_access
  override_during = plan
  values = {
    arn  = "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecr-cache-fixture"
    id   = "ona-runner-51cf5b27370de-ecr-cache-fixture"
    name = "ona-runner-51cf5b27370de-ecr-cache-fixture"
  }
}

override_resource {
  target          = aws_lambda_function.runner_control
  override_during = plan
  values          = { arn = "arn:aws:lambda:us-east-1:123456789012:function:test-runner-control" }
}

override_resource {
  target          = aws_s3_bucket.container_registry
  override_during = plan
  values          = { arn = "arn:aws:s3:::test-registry" }
}

override_resource {
  target          = aws_s3_bucket.agent
  override_during = plan
  values          = { arn = "arn:aws:s3:::test-agent-bucket" }
}

override_resource {
  target          = aws_s3_bucket.logs
  override_during = plan
  values          = { arn = "arn:aws:s3:::test-logs-bucket" }
}

override_resource {
  target          = aws_iam_policy.devcontainer_cache_boundary
  override_during = plan
  values = {
    arn  = "arn:aws:iam::123456789012:policy/ona-runner-51cf5b27370de-ecr-boundary-fixture"
    id   = "arn:aws:iam::123456789012:policy/ona-runner-51cf5b27370de-ecr-boundary-fixture"
    name = "ona-runner-51cf5b27370de-ecr-boundary-fixture"
  }
}

override_resource {
  target          = aws_iam_policy.confined_runner_boundary
  override_during = plan
  values = {
    arn  = "arn:aws:iam::123456789012:policy/ona-runner-51cf5b27370de-confined-boundary-fixture"
    id   = "arn:aws:iam::123456789012:policy/ona-runner-51cf5b27370de-confined-boundary-fixture"
    name = "ona-runner-51cf5b27370de-confined-boundary-fixture"
  }
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
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecs-task-fixture",
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
      "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecs-task-fixture",
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
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).identifiers == toset(["arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecs-task-fixture"]) &&
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
    condition = try(
      one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).actions == toset(["sts:AssumeRole", "sts:TagSession"]) &&
      one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset(["arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecs-task-fixture"]) &&
      length(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).condition) == 0, false
    )
    error_message = "Legacy devcontainer cache trust must preserve the original task principal and unconstrained session-tag behavior."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.devcontainer_cache_registry_access.statement :
      statement.resources == toset(["arn:aws:ecr:us-east-1:123456789012:repository/gitpod-runner-$${aws:PrincipalTag/gitpod.dev/runner-id}/projects/$${aws:PrincipalTag/gitpod.dev/project-id}/image-build"])
      if statement.sid == "AllowPullFromProject" || statement.sid == "AllowPushToProject"
      ]) && anytrue([
      for statement in data.aws_iam_policy_document.devcontainer_cache_registry_access.statement :
      statement.sid == "AllowPushToProject" && one(statement.condition).variable == "aws:PrincipalTag/gitpod.dev/push" && one(statement.condition).values == tolist(["true"])
    ])
    error_message = "Legacy delegated cache access must preserve session runner/project resources and the existing dormant push condition."
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

run "legacy_release_preserves_existing_addresses_and_authority" {
  command = plan

  assert {
    condition = (
      length(aws_iam_role.confined_runner) == 0 &&
      length(aws_iam_role.runner_control) == 0 &&
      length(aws_lambda_function.runner_control) == 0 &&
      length(aws_ecs_task_definition.confined_runner_baseline) == 0 &&
      aws_ecs_service.runner.task_definition == aws_ecs_task_definition.runner.arn &&
      aws_iam_role.ecs_task.assume_role_policy == data.aws_iam_policy_document.fargate_task_assume_role.json
    )
    error_message = "legacy must retain the existing task/role addresses and behavior without control resources."
  }
}

run "prepare_constructs_control_without_cutover" {
  command = plan

  variables {
    runner_iam_phase        = "prepare"
    custom_ca_trust_bundle  = "s3://gitpod-customer-ca/shared/ca-bundle.pem"
    custom_ca_s3_object_arn = "arn:aws:s3:::gitpod-customer-ca/shared/ca-bundle.pem"
  }

  assert {
    condition = (
      local.capable_runner_release && local.runner_control_source_is_valid &&
      length(aws_lambda_function.runner_control) == 1 &&
      length(aws_ecs_task_definition.confined_runner_baseline) == 1 &&
      aws_ecs_service.runner.task_definition == aws_ecs_task_definition.runner.arn &&
      local.runner_control_targets[0].baselineTaskDefinition == one(aws_ecs_task_definition.confined_runner_baseline).arn &&
      one(aws_iam_role_policy.runner_control).role == one(aws_iam_role.runner_control).id &&
      one(aws_iam_role_policy.confined_runner).role == one(aws_iam_role.confined_runner).id
    )
    error_message = "prepare must build the validated control path and immutable baseline while keeping the legacy task selected."
  }


  assert {
    condition = (
      alltrue([
        for container in local.confined_runner_container_definitions :
        endswith(container.image, "@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
      ]) &&
      one([for container in local.confined_runner_container_definitions : container if container.name == "ec2-runner"]).environment[index(one([for container in local.confined_runner_container_definitions : container if container.name == "ec2-runner"]).environment[*].name, "GITPOD_RUNNER_CONTROL_REQUIRED")].value == "true" &&
      local.runner_control_environment.RELEASES_URL == "https://releases.gitpod.io" &&
      local.runner_control_environment.APPROVED_IMAGE_IDS == "ami-00000000000000001,ami-00000000000000002"
    )
    error_message = "The prepared baseline and control function must render pinned images and verified control settings."
  }

  assert {
    condition = alltrue([
      for statement in one(data.aws_iam_policy_document.runner_control).statement :
      statement.resources == toset([
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-conf-task-fixture",
        "arn:aws:iam::123456789012:role/test-execution",
        "arn:aws:iam::123456789012:role/test-proxy",
      ]) && one(statement.condition).values == tolist(["ecs-tasks.amazonaws.com"])
      if statement.sid == "PassFixedTaskRoles"
    ])
    error_message = "the control function must pass only the fixed task and execution roles to ECS."
  }

  assert {
    condition = one([
      for statement in one(data.aws_iam_policy_document.runner_control).statement : statement
      if statement.sid == "UpdateOwnedServices"
      ]).resources == toset([
      "arn:aws:ecs:us-east-1:123456789012:service/ona-runner-51cf5b27370ded93-ona-cluster/ona-runner-51cf5b27370ded93-adot",
      "arn:aws:ecs:us-east-1:123456789012:service/ona-runner-51cf5b27370ded93-ona-cluster/ona-runner-51cf5b27370ded93-proxy",
      "arn:aws:ecs:us-east-1:123456789012:service/ona-runner-51cf5b27370ded93-ona-cluster/ona-runner-51cf5b27370ded93-runner",
    ])
    error_message = "the control function must update only this deployment's runner services."
  }

  assert {
    condition = alltrue([
      for action in ["ecs:RegisterTaskDefinition", "ecs:UpdateService", "iam:PassRole", "ec2:RunInstances", "ssm:SendCommand"] :
      !anytrue([for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : contains(statement.actions, action)])
    ])
    error_message = "the confined task boundary must leave task registration, service mutation, role passing, instance launch, and commands to the control function."
  }
}

run "confined_control_identity_contract" {
  command = plan
  variables { runner_iam_phase = "prepare" }
  assert {
    condition = (
      one(aws_iam_role_policy.confined_runner_control).role == one(aws_iam_role.confined_runner).id &&
      one(one(data.aws_iam_policy_document.confined_runner_control).statement).actions == toset(["lambda:InvokeFunction"]) &&
      one(one(data.aws_iam_policy_document.confined_runner_control).statement).resources == toset(["arn:aws:lambda:us-east-1:123456789012:function:test-runner-control"]) &&
      anytrue([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement :
        statement.sid == "InvokeRunnerControl" && statement.actions == toset(["lambda:InvokeFunction"]) && statement.resources == toset(["arn:aws:lambda:us-east-1:123456789012:function:ona-runner-51cf5b27370ded93-runner-control"])
      ])
    )
    error_message = "The actual confined role identity and boundary must both allow only this deployment's runner-control function."
  }
}

run "managed_cache_session_contract" {
  command = plan
  variables { runner_iam_phase = "prepare" }

  assert {
    condition = (
      one([
        for statement in data.aws_iam_policy_document.ecs_task.statement : statement
        if statement.sid == "AssumeRunnerManagedRoles"
        ]).resources == toset([
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecr-cache-fixture",
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-s3-access-fixture",
      ]) &&
      one([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "AssumeExactCacheRoles"
        ]).resources == toset([
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecr-cache-*",
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-s3-access-*",
      ]) &&
      aws_iam_role.devcontainer_cache_registry_access.permissions_boundary == aws_iam_policy.devcontainer_cache_boundary.arn &&
      aws_iam_role_policy.devcontainer_cache_registry_access.role == aws_iam_role.devcontainer_cache_registry_access.id
    )
    error_message = "Managed cache delegation must intersect the runtime identity, its runner-specific boundary, and the delegated role boundary at the actual attached roles."
  }

  assert {
    condition = (
      aws_iam_role.devcontainer_cache_registry_access.name_prefix == "ona-runner-51cf5b27370de-ecr-cache-" &&
      aws_iam_role.devcontainer_cache_registry_access.name == "ona-runner-51cf5b27370de-ecr-cache-fixture" &&
      aws_iam_role.devcontainer_cache_registry_access.arn == "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecr-cache-fixture" &&
      aws_iam_role.devcontainer_cache_registry_access.id == aws_iam_role_policy.devcontainer_cache_registry_access.role &&
      aws_iam_role.devcontainer_cache_registry_access.permissions_boundary == "arn:aws:iam::123456789012:policy/ona-runner-51cf5b27370de-ecr-boundary-fixture" &&
      startswith(aws_iam_role.devcontainer_cache_registry_access.name, trimsuffix(aws_iam_role.devcontainer_cache_registry_access.name_prefix, "-"))
    )
    error_message = "The rendered cache role, inline attachment, and boundary must use one internally consistent generated-name identity."
  }

  assert {
    condition = try(
      one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset([
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-conf-task-fixture",
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecs-task-fixture",
      ]) &&
      length(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).condition) == 6 &&
      alltrue([
        for condition in one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).condition :
        (condition.test == "StringEquals" && condition.variable == "aws:RequestTag/gitpod.dev/runner-id" && condition.values == tolist(["runner-a"])) ||
        (condition.test == "StringLike" && condition.variable == "aws:RequestTag/gitpod.dev/project-id" && condition.values == tolist(["?*"])) ||
        (condition.test == "StringEquals" && condition.variable == "aws:RequestTag/gitpod.dev/allow-push" && toset(condition.values) == toset(["false", "true"])) ||
        (condition.test == "ForAllValues:StringEquals" && condition.variable == "aws:TagKeys" && toset(condition.values) == toset(["gitpod.dev/runner-id", "gitpod.dev/project-id", "gitpod.dev/environment-creator-id", "gitpod.dev/allow-push"])) ||
        (condition.test == "Null" && contains(["aws:RequestTag/gitpod.dev/runner-id", "aws:RequestTag/gitpod.dev/project-id"], condition.variable) && condition.values == tolist(["false"]))
      ]) &&
      alltrue([
        for statement in data.aws_iam_policy_document.devcontainer_cache_registry_access.statement :
        statement.resources == toset(["arn:aws:ecr:us-east-1:123456789012:repository/gitpod-runner-runner-a/projects/$${aws:PrincipalTag/gitpod.dev/project-id}/image-build"])
        if statement.sid == "AllowPullFromProject" || statement.sid == "AllowPushToProject"
      ]), false
    )
    error_message = "Managed cache trust must admit the real four-tag request contract, reject unsupported tags, and bind resources to the configured runner."
  }

  assert {
    condition = (
      one([
        for statement in data.aws_iam_policy_document.devcontainer_cache_registry_access.statement : statement
        if statement.sid == "AllowPullFromProject"
      ]).actions == toset(["ecr:BatchGetImage", "ecr:DescribeImages", "ecr:DescribeRepositories"]) &&
      one([
        for statement in data.aws_iam_policy_document.devcontainer_cache_registry_access.statement : statement
        if statement.sid == "AllowPushToProject"
      ]).actions == toset(["ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:BatchCheckLayerAvailability"]) &&
      one(one([
        for statement in data.aws_iam_policy_document.devcontainer_cache_registry_access.statement : statement
        if statement.sid == "AllowPushToProject"
      ]).condition).variable == "aws:PrincipalTag/gitpod.dev/push" &&
      one([
        for statement in data.aws_iam_policy_document.devcontainer_cache_registry_access.statement : statement
        if statement.sid == "AllowGetAuthorizationToken"
      ]).resources == toset(["*"])
    )
    error_message = "The existing cache identity policy must retain its bounded reads, dormant push condition, and identity-only authorization token grant."
  }
}

run "runner_control_task_definition_scope" {
  command = plan
  variables { runner_iam_phase = "prepare" }
  assert {
    condition = (
      one([
        for statement in one(data.aws_iam_policy_document.runner_control).statement : statement
        if statement.sid == "DescribeTaskDefinitions"
      ]).resources == toset(["*"]) &&
      length(one([
        for statement in one(data.aws_iam_policy_document.runner_control).statement : statement
        if statement.sid == "RegisterOwnedTaskDefinitions"
      ]).resources) == 2 &&
      alltrue([for resource in one([
        for statement in one(data.aws_iam_policy_document.runner_control).statement : statement
        if statement.sid == "RegisterOwnedTaskDefinitions"
      ]).resources : startswith(resource, "arn:aws:ecs:us-east-1:123456789012:task-definition/") && endswith(resource, ":*")]) &&
      !contains(one([
        for statement in one(data.aws_iam_policy_document.runner_control).statement : statement
        if statement.sid == "RegisterOwnedTaskDefinitions"
      ]).actions, "ecs:DescribeTaskDefinition")
    )
    error_message = "DescribeTaskDefinition must use Resource *, while registration remains limited to the configured task families."
  }
}

run "confined_ca_scope_contract" {
  command = plan
  variables {
    runner_iam_phase        = "prepare"
    custom_ca_trust_bundle  = "s3://gitpod-customer-ca/shared/ca-bundle.pem"
    custom_ca_s3_object_arn = "arn:aws:s3:::gitpod-customer-ca/shared/ca-bundle.pem"
  }
  assert {
    condition = (
      one(aws_iam_role_policy.confined_runner_ca).role == one(aws_iam_role.confined_runner).id &&
      one(one(data.aws_iam_policy_document.confined_runner_ca).statement).actions == toset(["s3:GetObject"]) &&
      one(one(data.aws_iam_policy_document.confined_runner_ca).statement).resources == toset(["arn:aws:s3:::gitpod-customer-ca/shared/ca-bundle.pem"]) &&
      one([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "ReadConfiguredCABundle"
      ]).actions == toset(["s3:GetObject"]) &&
      one([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "ReadConfiguredCABundle"
      ]).resources == toset(["arn:aws:s3:::gitpod-customer-ca/shared/ca-bundle.pem"]) &&
      length([for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement if statement.sid == "ReadCABundles"]) == 0 &&
      one([for item in local.confined_ca_init_container.environment : item.value if item.name == "GITPOD_CUSTOM_CA_S3_OBJECT_ARN"]) == "arn:aws:s3:::gitpod-customer-ca/shared/ca-bundle.pem" &&
      one([for item in local.confined_ca_init_container.environment : item.value if item.name == "GITPOD_CUSTOM_CA_S3_SCOPE_REQUIRED"]) == "true" &&
      length([for item in local.ca_init_container.environment : item if startswith(item.name, "GITPOD_CUSTOM_CA_S3_")]) == 0
    )
    error_message = "Only the confined init identity may require and receive the exact declared CA object scope; legacy and sibling init definitions stay unchanged."
  }
}

run "confined_external_ca_identity_contract" {
  command = plan
  variables {
    runner_iam_phase        = "prepare"
    custom_ca_trust_bundle  = "s3://customer-ca-bucket/shared/ca-bundle.pem"
    custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket/shared/ca-bundle.pem"
  }

  assert {
    condition = (
      one(aws_ecs_task_definition.confined_runner_baseline).task_role_arn == one(aws_iam_role.confined_runner).arn &&
      aws_ecs_service.runner.task_definition == aws_ecs_task_definition.runner.arn
    )
    error_message = "Prepare must bind the dormant confined baseline to the confined role while the service stays on the legacy task."
  }

  assert {
    condition = (
      one(aws_iam_role_policy.confined_runner_ca).role == one(aws_iam_role.confined_runner).id &&
      jsondecode(one(aws_iam_role_policy.confined_runner_ca).policy) == jsondecode(one(data.aws_iam_policy_document.confined_runner_ca).json)
    )
    error_message = "The external CA identity document must be attached to the actual confined role."
  }

  assert {
    condition     = one(aws_iam_role.confined_runner).permissions_boundary == one(aws_iam_policy.confined_runner_boundary).arn
    error_message = "The matching boundary document must be attached to the actual confined role."
  }

  assert {
    condition = (
      one(one(data.aws_iam_policy_document.confined_runner_ca).statement).actions == toset(["s3:GetObject"]) &&
      one(one(data.aws_iam_policy_document.confined_runner_ca).statement).resources == toset(["arn:aws:s3:::customer-ca-bucket/shared/ca-bundle.pem"]) &&
      coalesce(one(one(data.aws_iam_policy_document.confined_runner_ca).statement).effect, "Allow") == "Allow" &&
      length(one(data.aws_iam_policy_document.confined_runner_ca).statement) == 1 &&
      one([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "ReadConfiguredCABundle"
      ]).resources == toset(["arn:aws:s3:::customer-ca-bucket/shared/ca-bundle.pem"]) &&
      !contains(one(one(data.aws_iam_policy_document.confined_runner_ca).statement).actions, "s3:PutObject") &&
      !contains(one(one(data.aws_iam_policy_document.confined_runner_ca).statement).actions, "s3:DeleteObject") &&
      !contains(one(one(data.aws_iam_policy_document.confined_runner_ca).statement).actions, "s3:ListBucket")
    )
    error_message = "The confined identity and boundary must allow only GetObject on the declared external CA object."
  }
}

run "confined_empty_ca_scope_contract" {
  command = plan
  variables { runner_iam_phase = "prepare" }

  assert {
    condition = (
      length([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "ReadConfiguredCABundle"
      ]) == 0 &&
      length(data.aws_iam_policy_document.confined_runner_ca) == 0 &&
      length(aws_iam_role_policy.confined_runner_ca) == 0 &&
      anytrue([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement :
        statement.sid == "RunnerBuckets" && contains(statement.actions, "s3:GetObject") &&
        contains(statement.resources, "arn:aws:s3:::test-agent-bucket/*") &&
        contains(statement.resources, "arn:aws:s3:::test-logs-bucket/*")
      ]) &&
      one([for item in local.confined_ca_init_container.environment : item.value if item.name == "GITPOD_CUSTOM_CA_S3_OBJECT_ARN"]) == "" &&
      one([for item in local.confined_ca_init_container.environment : item.value if item.name == "GITPOD_CUSTOM_CA_S3_SCOPE_REQUIRED"]) == "true"
    )
    error_message = "The confined init must require the CA scope declaration even when it is empty, without creating an external S3 grant."
  }
}

run "legacy_ignores_external_ca_declaration" {
  command = plan
  variables {
    custom_ca_trust_bundle  = "s3://customer-ca-bucket/shared/ca-bundle.pem"
    custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket/shared/ca-bundle.pem"
  }

  assert {
    condition = (
      length(aws_iam_role.confined_runner) == 0 &&
      length(data.aws_iam_policy_document.confined_runner_ca) == 0 &&
      length(aws_iam_role_policy.confined_runner_ca) == 0 &&
      length([for item in local.ca_init_container.environment : item if startswith(item.name, "GITPOD_CUSTOM_CA_S3_")]) == 0
    )
    error_message = "An explicit CA declaration must not create confined authority or change the active legacy init environment in legacy phase."
  }
}

run "unused_external_ca_declaration_stays_explicit" {
  command = plan
  variables {
    runner_iam_phase        = "prepare"
    custom_ca_trust_bundle  = "https://ca.example.com/root.pem"
    custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket/unused/root.pem"
  }

  assert {
    condition = (
      one(one(data.aws_iam_policy_document.confined_runner_ca).statement).resources == toset(["arn:aws:s3:::customer-ca-bucket/unused/root.pem"]) &&
      one([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "ReadConfiguredCABundle"
      ]).resources == toset(["arn:aws:s3:::customer-ca-bucket/unused/root.pem"])
    )
    error_message = "A valid declaration remains explicit authority even when the current CA value is HTTP; removing the declaration removes that authority."
  }
}

run "external_ca_declaration_switches_exact_key" {
  command = plan
  variables {
    runner_iam_phase        = "prepare"
    custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket/rotated/ca-bundle.pem"
  }

  assert {
    condition = (
      one(one(data.aws_iam_policy_document.confined_runner_ca).statement).resources == toset(["arn:aws:s3:::customer-ca-bucket/rotated/ca-bundle.pem"]) &&
      !contains(one(one(data.aws_iam_policy_document.confined_runner_ca).statement).resources, "arn:aws:s3:::customer-ca-bucket/shared/ca-bundle.pem") &&
      one([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "ReadConfiguredCABundle"
      ]).resources == toset(["arn:aws:s3:::customer-ca-bucket/rotated/ca-bundle.pem"])
    )
    error_message = "Changing the declaration must move both grants to the new exact key without retaining the prior key or another bucket."
  }
}

run "confined_catalog_read_contract" {
  command = plan
  variables { runner_iam_phase = "prepare" }
  assert {
    condition = (
      one([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : statement
        if statement.sid == "DescribeComputeCatalog"
        ]).actions == toset([
        "autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribePolicies", "autoscaling:DescribeWarmPool",
        "ec2:DescribeInstanceStatus", "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeInstanceTypes",
        "ec2:DescribeInternetGateways", "ec2:DescribeNatGateways", "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeTags",
        "ec2:DescribeVpcAttribute", "ec2:DescribeVpcEndpoints", "ec2:DescribeVpcs", "ssm:DescribeParameters",
      ]) &&
      alltrue([
        for action in ["ec2:DescribeImages", "ec2:DescribeInstanceAttribute", "ec2:DescribeInstances", "ec2:DescribeLaunchTemplates", "ec2:DescribeLaunchTemplateVersions", "ec2:DescribeSnapshots", "ec2:DescribeVolumes", "ssm:GetCommandInvocation"] :
        !anytrue([for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement : contains(statement.actions, action)])
      ])
    )
    error_message = "The confined runtime must keep only explicit catalog reads; owner-sensitive reads and command output remain broker-mediated."
  }
}

run "confined_owned_compute_contract" {
  command = plan
  variables { runner_iam_phase = "prepare" }
  assert {
    condition = (
      anytrue([
        for statement in data.aws_iam_policy_document.ecs_task.statement :
        contains(statement.actions, "ec2:CreateTags") && contains(statement.actions, "ec2:DeleteTags")
      ]) &&
      anytrue([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement :
        statement.sid == "TagOwnedComputeMetadata" && contains(statement.actions, "ec2:CreateTags") && contains(statement.actions, "ec2:DeleteTags") &&
        one(statement.condition).variable == "ec2:ResourceTag/gitpod.dev/runner-id"
      ]) &&
      anytrue([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement :
        statement.sid == "DenyRunnerOwnerReassignment" && statement.effect == "Deny" && contains([for condition in statement.condition : condition.variable], "aws:RequestTag/gitpod.dev/runner-id")
      ]) &&
      anytrue([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement :
        statement.sid == "DenyRunnerOwnerTagDeletion" && statement.effect == "Deny" && one(statement.condition).test == "ForAnyValue:StringEquals"
      ]) &&
      anytrue([
        for statement in one(data.aws_iam_policy_document.confined_runner_boundary).statement :
        statement.sid == "OwnedComputeMutation" && contains(statement.actions, "ec2:DeleteLaunchTemplate") && contains(statement.actions, "ec2:CancelSpotInstanceRequests") &&
        contains(statement.resources, "arn:aws:ec2:us-east-1:123456789012:launch-template/*") &&
        contains(statement.resources, "arn:aws:ec2:us-east-1:123456789012:spot-instances-request/*")
      ])
    )
    error_message = "Owned metadata updates, launch-template deletion, and spot cancellation need identity and boundary grants while owner reassignment and deletion remain explicit denies."
  }
}

run "custom_ca_object_arn_rejects_bucket_scope" {
  command = plan
  variables { custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket" }
  expect_failures = [var.custom_ca_s3_object_arn]
}

run "custom_ca_object_arn_rejects_wildcards" {
  command = plan
  variables { custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket/*" }
  expect_failures = [var.custom_ca_s3_object_arn]
}

run "custom_ca_object_arn_rejects_policy_expansion" {
  command = plan
  variables { custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket/$${aws:username}.pem" }
  expect_failures = [var.custom_ca_s3_object_arn]
}

run "custom_ca_object_arn_rejects_unsupported_partition" {
  command = plan
  variables { custom_ca_s3_object_arn = "arn:aws-us-gov:s3:::customer-ca-bucket/shared/ca-bundle.pem" }
  expect_failures = [var.custom_ca_s3_object_arn]
}

run "cutover_selects_the_immutable_baseline" {
  command = plan

  variables {
    runner_iam_phase        = "cutover"
    custom_ca_s3_object_arn = "arn:aws:s3:::customer-ca-bucket/shared/ca-bundle.pem"
  }

  assert {
    condition = (
      aws_ecs_service.runner.task_definition == one(aws_ecs_task_definition.confined_runner_baseline).arn &&
      one(aws_ecs_task_definition.confined_runner_baseline).task_role_arn == one(aws_iam_role.confined_runner).arn &&
      one(aws_iam_role_policy.confined_runner_ca).role == one(aws_iam_role.confined_runner).id &&
      aws_iam_role.ecs_task.assume_role_policy == data.aws_iam_policy_document.fargate_task_assume_role.json &&
      one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset([
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-conf-task-fixture",
        "arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-ecs-task-fixture",
      ])
    )
    error_message = "cutover must select the confined baseline while retaining legacy rollback trust."
  }
}

run "confined_retires_legacy_authority" {
  command = plan

  variables {
    runner_iam_phase                = "confined"
    runner_iam_retirement_confirmed = true
    custom_ca_s3_object_arn         = "arn:aws:s3:::customer-ca-bucket/shared/ca-bundle.pem"
  }

  assert {
    condition = (
      aws_ecs_service.runner.task_definition == one(aws_ecs_task_definition.confined_runner_baseline).arn &&
      one(aws_ecs_task_definition.confined_runner_baseline).task_role_arn == one(aws_iam_role.confined_runner).arn &&
      one(aws_iam_role_policy.confined_runner_ca).role == one(aws_iam_role.confined_runner).id &&
      aws_iam_role.ecs_task.assume_role_policy == data.aws_iam_policy_document.retired_runner_assume.json &&
      jsondecode(aws_iam_role_policy.ecs_task.policy) == jsondecode(data.aws_iam_policy_document.retired_runner.json) &&
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).identifiers == toset(["arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-conf-task-fixture"]) &&
      one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset(["arn:aws:iam::123456789012:role/ona-runner-51cf5b27370de-conf-task-fixture"])
    )
    error_message = "confined must keep the legacy address inert and trust only the confined task for delegated cache sessions."
  }
}

run "confined_requires_retirement_confirmation" {
  command = plan

  variables {
    runner_iam_phase = "confined"
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "digest_only_release_does_not_advertise_control" {
  command = plan

  variables {
    runner_iam_phase = "prepare"
  }

  override_data {
    target = data.http.runner_release_manifest
    values = {
      response_body = <<-JSON
        {"version":"20260917.657","image_digest":"public.ecr.aws/example/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","proxy_image_digest":"public.ecr.aws/example/proxy@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","cloudformation_template_url":"https://releases.gitpod.io/ec2/releases/20260917.657/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"}
      JSON
    }
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "string_protocol_fails_closed" {
  command = plan

  variables {
    runner_iam_phase = "prepare"
  }

  override_data {
    target = data.http.runner_release_manifest
    values = {
      response_body = <<-JSON
        {"version":"20260917.657","image_digest":"public.ecr.aws/example/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","proxy_image_digest":"public.ecr.aws/example/proxy@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runner_control_protocol":"1","runner_control_source_sha256":"sha256:61e3e54dc5206a73859ff79d1e723648214b0d6510f96b3c665f561aca60c2d6","cloudformation_template_url":"https://releases.gitpod.io/ec2/releases/20260917.657/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"}
      JSON
    }
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "source_hash_without_protocol_fails_closed" {
  command = plan

  variables {
    runner_iam_phase = "prepare"
  }

  override_data {
    target = data.http.runner_release_manifest
    values = {
      response_body = <<-JSON
        {"version":"20260917.657","image_digest":"public.ecr.aws/example/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","proxy_image_digest":"public.ecr.aws/example/proxy@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runner_control_source_sha256":"sha256:61e3e54dc5206a73859ff79d1e723648214b0d6510f96b3c665f561aca60c2d6","cloudformation_template_url":"https://releases.gitpod.io/ec2/releases/20260917.657/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"}
      JSON
    }
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "mismatched_control_source_fails_closed" {
  command = plan

  variables {
    runner_iam_phase = "prepare"
  }

  override_data {
    target = data.http.runner_release_manifest
    values = {
      response_body = <<-JSON
        {"version":"20260917.657","image_digest":"public.ecr.aws/example/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","proxy_image_digest":"public.ecr.aws/example/proxy@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runner_control_protocol":1,"runner_control_source_sha256":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","cloudformation_template_url":"https://releases.gitpod.io/ec2/releases/20260917.657/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"}
      JSON
    }
  }

  expect_failures = [aws_ecs_cluster.this]
}
