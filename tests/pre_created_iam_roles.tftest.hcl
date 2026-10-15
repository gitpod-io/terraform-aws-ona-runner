# Real policy-document evaluation with synthetic AWS read/resource fixtures.
# No AWS API calls or resources are applied.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target          = data.aws_caller_identity.current
  override_during = plan
  values          = { account_id = "123456789012" }
}
override_data {
  target          = data.aws_region.current
  override_during = plan
  values          = { region = "us-east-1", name = "us-east-1" }
}
variables {
  runner_id                = "synthetic-runner"
  runner_token             = "synthetic-token"
  runner_domain            = "runner.example.com"
  certificate_arn          = "arn:aws:acm:us-east-1:123456789012:certificate/test"
  vpc_id                   = "vpc-00000000000000000"
  runner_subnet_ids        = ["subnet-00000000000000000"]
  load_balancer_subnet_ids = ["subnet-00000000000000000"]
}
override_resource {
  target          = aws_iam_role.ecs_execution
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/module-ecs-execution", name = "module-ecs-execution", id = "module-ecs-execution" }
}
override_data {
  target          = data.aws_iam_role.pre_created["ecs_execution"]
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-execution" }
}
override_resource {
  target          = aws_iam_role.ecs_task
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/module-ecs-task", name = "module-ecs-task", id = "module-ecs-task" }
}
override_data {
  target          = data.aws_iam_role.pre_created["ecs_task"]
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-task" }
}
override_resource {
  target          = aws_iam_role.proxy
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/module-proxy", name = "module-proxy", id = "module-proxy" }
}
override_data {
  target          = data.aws_iam_role.pre_created["proxy"]
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/customer/platform/customer-proxy" }
}
override_resource {
  target          = aws_iam_role.adot
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/module-adot", name = "module-adot", id = "module-adot" }
}
override_data {
  target          = data.aws_iam_role.pre_created["adot"]
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/customer/platform/customer-adot" }
}
override_resource {
  target          = aws_iam_role.environment
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/module-environment", name = "module-environment", id = "module-environment" }
}
override_data {
  target          = data.aws_iam_role.pre_created["environment"]
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/customer/platform/customer-environment" }
}
override_resource {
  target          = aws_iam_role.s3_access
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/module-s3-access", name = "module-s3-access", id = "module-s3-access" }
}
override_data {
  target          = data.aws_iam_role.pre_created["s3_access"]
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/customer/platform/customer-s3-access" }
}
override_resource {
  target          = aws_iam_role.devcontainer_cache_registry_access
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/module-devcontainer-cache-registry-access", name = "module-devcontainer-cache-registry-access", id = "module-devcontainer-cache-registry-access" }
}
override_data {
  target          = data.aws_iam_role.pre_created["devcontainer_cache_registry_access"]
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/customer/platform/customer-devcontainer-cache-registry-access" }
}
override_resource {
  target          = aws_iam_instance_profile.environment
  override_during = plan
  values          = { name = "module-environment-profile" }
}
override_data {
  target          = data.aws_iam_instance_profile.environment
  override_during = plan
  values          = { name = "customer-environment-profile", role_arn = "arn:aws:iam::123456789012:role/customer/platform/customer-environment" }
}
override_resource {
  target          = aws_s3_bucket.container_registry
  override_during = plan
  values          = { arn = "arn:aws:s3:::synthetic-container-registry", bucket = "synthetic-container-registry" }
}
override_resource {
  target          = aws_s3_bucket.agent
  override_during = plan
  values          = { arn = "arn:aws:s3:::synthetic-agent", bucket = "synthetic-agent" }
}
override_resource {
  target          = aws_s3_bucket.logs
  override_during = plan
  values          = { arn = "arn:aws:s3:::synthetic-logs", bucket = "synthetic-logs" }
}
override_resource {
  target          = aws_cloudwatch_log_group.runner
  override_during = plan
  values          = { name = "/gitpod/synthetic-runner" }
}
override_resource {
  target          = aws_cloudwatch_log_group.proxy
  override_during = plan
  values          = { name = "/gitpod/synthetic-proxy" }
}
override_resource {
  target          = aws_cloudwatch_log_group.adot
  override_during = plan
  values          = { name = "/gitpod/synthetic-adot" }
}
override_resource {
  target          = aws_dynamodb_table.resources
  override_during = plan
  values          = { arn = "arn:aws:dynamodb:us-east-1:123456789012:table/synthetic-resources", name = "synthetic-resources" }
}

override_resource {
  target          = aws_iam_policy.ecs_execution_boundary
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:policy/ecs_execution_boundary" }
}
override_resource {
  target          = aws_iam_policy.ecs_task_boundary
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:policy/ecs_task_boundary" }
}
override_resource {
  target          = aws_iam_policy.proxy_boundary
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:policy/proxy_boundary" }
}
override_resource {
  target          = aws_iam_policy.adot_boundary
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:policy/adot_boundary" }
}
override_resource {
  target          = aws_iam_policy.environment_boundary
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:policy/environment_boundary" }
}
override_resource {
  target          = aws_iam_policy.s3_access_boundary
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:policy/s3_access_boundary" }
}
override_resource {
  target          = aws_iam_policy.devcontainer_cache_boundary
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:policy/devcontainer_cache_boundary" }
}

override_resource {
  target          = aws_security_group.environment
  override_during = plan
  values          = { id = "sg-00000000000000000" }
}

run "default_iam_ownership" {
  command = plan
  assert {
    condition = (
      length(aws_iam_role.ecs_execution) == 1 &&
      length(aws_iam_role.ecs_task) == 1 &&
      length(aws_iam_role.proxy) == 1 &&
      length(aws_iam_role.adot) == 1 &&
      length(aws_iam_role.environment) == 1 &&
      length(aws_iam_role.s3_access) == 1 &&
      length(aws_iam_role.devcontainer_cache_registry_access) == 1 &&
      length(aws_iam_role_policy.ecs_execution) == 1 &&
      length(aws_iam_role_policy.ecs_task) == 1 &&
      length(aws_iam_role_policy.proxy) == 1 &&
      length(aws_iam_role_policy.adot) == 1 &&
      length(aws_iam_role_policy.environment) == 1 &&
      length(aws_iam_role_policy.s3_access) == 1 &&
      length(aws_iam_role_policy.devcontainer_cache_registry_access) == 1 &&
      length(aws_iam_policy.ecs_execution_boundary) == 1 &&
      length(aws_iam_policy.ecs_task_boundary) == 1 &&
      length(aws_iam_policy.proxy_boundary) == 1 &&
      length(aws_iam_policy.adot_boundary) == 1 &&
      length(aws_iam_policy.environment_boundary) == 1 &&
      length(aws_iam_policy.s3_access_boundary) == 1 &&
      length(aws_iam_policy.devcontainer_cache_boundary) == 1 && length(aws_iam_role_policy_attachment.ecs_execution) == 1 && length(data.aws_iam_role.pre_created) == 0
    )
    error_message = "Default deployments must create all seven roles, boundaries and permission policies."
  }
  assert {
    condition = (
      output.ecs_execution_role_arn == "arn:aws:iam::123456789012:role/module-ecs-execution" &&
      output.ecs_task_role_arn == "arn:aws:iam::123456789012:role/module-ecs-task" &&
      output.proxy_role_arn == "arn:aws:iam::123456789012:role/module-proxy" &&
      output.adot_role_arn == "arn:aws:iam::123456789012:role/module-adot" &&
      output.environment_role_arn == "arn:aws:iam::123456789012:role/module-environment" &&
      output.s3_access_role_arn == "arn:aws:iam::123456789012:role/module-s3-access" &&
      output.devcontainer_cache_registry_access_role_arn == "arn:aws:iam::123456789012:role/module-devcontainer-cache-registry-access"
    )
    error_message = "Default outputs must expose module-created roles."
  }
  assert {
    condition = (
      length(aws_iam_instance_profile.environment) == 1 && output.environment_instance_profile_name == "module-environment-profile"
    )
    error_message = "The environment profile remains module-managed by default."
  }
  assert {
    condition = (
      aws_iam_role.ecs_execution[0].permissions_boundary == aws_iam_policy.ecs_execution_boundary[0].arn &&
      aws_iam_role.ecs_task[0].permissions_boundary == aws_iam_policy.ecs_task_boundary[0].arn &&
      aws_iam_role.proxy[0].permissions_boundary == aws_iam_policy.proxy_boundary[0].arn &&
      aws_iam_role.adot[0].permissions_boundary == aws_iam_policy.adot_boundary[0].arn &&
      aws_iam_role.environment[0].permissions_boundary == aws_iam_policy.environment_boundary[0].arn &&
      aws_iam_role.s3_access[0].permissions_boundary == aws_iam_policy.s3_access_boundary[0].arn &&
      aws_iam_role.devcontainer_cache_registry_access[0].permissions_boundary == aws_iam_policy.devcontainer_cache_boundary[0].arn
    )
    error_message = "Every created role must retain its own permission boundary."
  }
}

run "pre_created_without_attachments" {
  command = plan
  variables {
    pre_created_iam_roles = {
      ecs_execution                      = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-execution"
      ecs_task                           = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-task"
      proxy                              = "arn:aws:iam::123456789012:role/customer/platform/customer-proxy"
      adot                               = "arn:aws:iam::123456789012:role/customer/platform/customer-adot"
      environment                        = "arn:aws:iam::123456789012:role/customer/platform/customer-environment"
      s3_access                          = "arn:aws:iam::123456789012:role/customer/platform/customer-s3-access"
      devcontainer_cache_registry_access = "arn:aws:iam::123456789012:role/customer/platform/customer-devcontainer-cache-registry-access"
    }
    environment_instance_profile_name = "customer-environment-profile"
  }
  assert {
    condition = (
      length(aws_iam_role.ecs_execution) == 0 &&
      length(aws_iam_role.ecs_task) == 0 &&
      length(aws_iam_role.proxy) == 0 &&
      length(aws_iam_role.adot) == 0 &&
      length(aws_iam_role.environment) == 0 &&
      length(aws_iam_role.s3_access) == 0 &&
      length(aws_iam_role.devcontainer_cache_registry_access) == 0 &&
      length(aws_iam_role_policy.ecs_execution) == 0 &&
      length(aws_iam_role_policy.ecs_task) == 0 &&
      length(aws_iam_role_policy.proxy) == 0 &&
      length(aws_iam_role_policy.adot) == 0 &&
      length(aws_iam_role_policy.environment) == 0 &&
      length(aws_iam_role_policy.s3_access) == 0 &&
      length(aws_iam_role_policy.devcontainer_cache_registry_access) == 0 &&
      length(aws_iam_policy.ecs_execution_boundary) == 0 &&
      length(aws_iam_policy.ecs_task_boundary) == 0 &&
      length(aws_iam_policy.proxy_boundary) == 0 &&
      length(aws_iam_policy.adot_boundary) == 0 &&
      length(aws_iam_policy.environment_boundary) == 0 &&
      length(aws_iam_policy.s3_access_boundary) == 0 &&
      length(aws_iam_policy.devcontainer_cache_boundary) == 0 && length(aws_iam_role_policy_attachment.ecs_execution) == 0
    )
    error_message = "Supplied roles must not be created or have policies or boundaries managed without opt-in."
  }
  assert {
    condition = (
      output.ecs_execution_role_arn == var.pre_created_iam_roles.ecs_execution &&
      output.ecs_task_role_arn == var.pre_created_iam_roles.ecs_task &&
      output.proxy_role_arn == var.pre_created_iam_roles.proxy &&
      output.adot_role_arn == var.pre_created_iam_roles.adot &&
      output.environment_role_arn == var.pre_created_iam_roles.environment &&
      output.s3_access_role_arn == var.pre_created_iam_roles.s3_access &&
      output.devcontainer_cache_registry_access_role_arn == var.pre_created_iam_roles.devcontainer_cache_registry_access
    )
    error_message = "All role outputs must expose the supplied identities."
  }
  assert {
    condition = (
      aws_ecs_task_definition.runner.execution_role_arn == output.ecs_execution_role_arn && aws_ecs_task_definition.proxy[0].execution_role_arn == output.ecs_execution_role_arn && aws_ecs_task_definition.adot.execution_role_arn == output.ecs_execution_role_arn && aws_ecs_task_definition.runner.task_role_arn == output.ecs_task_role_arn && aws_ecs_task_definition.proxy[0].task_role_arn == output.proxy_role_arn && aws_ecs_task_definition.adot.task_role_arn == output.adot_role_arn
    )
    error_message = "All task definitions must use the effective execution and application roles."
  }
  assert {
    condition = (
      jsondecode(local.runner_config).environmentRoleArn == output.environment_role_arn && jsondecode(local.runner_config).instanceProfileName == output.environment_instance_profile_name && jsondecode(local.runner_config).devContainerCacheRegistryAccessRoleArn == output.devcontainer_cache_registry_access_role_arn && one([for env in local.runner_container.environment : env.value if env.name == "S3_ACCESS_ROLE_ARN"]) == output.s3_access_role_arn
    )
    error_message = "Runner configuration and environment variables must use effective roles and profile."
  }
  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.container_registry_bucket.statement : s if s.sid == "DenyReadsExceptS3AccessRole"]).condition == toset([{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = tolist([output.s3_access_role_arn]) }]) && one(one(data.aws_iam_policy_document.dynamodb_resource.statement).condition).values == tolist([output.ecs_task_role_arn])
    )
    error_message = "Resource-policy deny exceptions must recognize the supplied S3 and runner roles."
  }
  assert {
    condition = (
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn]) && one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn])
    )
    error_message = "Both cache trust policies must name the effective runner role."
  }
  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "AssumeRunnerManagedRoles"]) == toset([output.s3_access_role_arn, output.devcontainer_cache_registry_access_role_arn]) && one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "PassEnvironmentRole"]) == toset([output.environment_role_arn]) && one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "PassECSTaskRoles"]) == toset([output.ecs_execution_role_arn, output.ecs_task_role_arn, output.proxy_role_arn])
    )
    error_message = "AssumeRole and PassRole grants must use the selected identities without broadening scopes."
  }
  assert {
    condition = (
      length(aws_iam_instance_profile.environment) == 0 && length(data.aws_iam_instance_profile.environment) == 1 && output.environment_instance_profile_name == "customer-environment-profile"
    )
    error_message = "A supplied profile must be read and reused, never created or modified."
  }
}

run "pre_created_with_attachments" {
  command = plan
  variables {
    pre_created_iam_roles = {
      ecs_execution                      = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-execution"
      ecs_task                           = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-task"
      proxy                              = "arn:aws:iam::123456789012:role/customer/platform/customer-proxy"
      adot                               = "arn:aws:iam::123456789012:role/customer/platform/customer-adot"
      environment                        = "arn:aws:iam::123456789012:role/customer/platform/customer-environment"
      s3_access                          = "arn:aws:iam::123456789012:role/customer/platform/customer-s3-access"
      devcontainer_cache_registry_access = "arn:aws:iam::123456789012:role/customer/platform/customer-devcontainer-cache-registry-access"
      attach_iam_policies                = true
    }
    environment_instance_profile_name = "customer-environment-profile"
  }
  assert {
    condition = (
      length(aws_iam_role.ecs_execution) == 0 &&
      length(aws_iam_role.ecs_task) == 0 &&
      length(aws_iam_role.proxy) == 0 &&
      length(aws_iam_role.adot) == 0 &&
      length(aws_iam_role.environment) == 0 &&
      length(aws_iam_role.s3_access) == 0 &&
      length(aws_iam_role.devcontainer_cache_registry_access) == 0 &&
      length(aws_iam_policy.ecs_execution_boundary) == 0 &&
      length(aws_iam_policy.ecs_task_boundary) == 0 &&
      length(aws_iam_policy.proxy_boundary) == 0 &&
      length(aws_iam_policy.adot_boundary) == 0 &&
      length(aws_iam_policy.environment_boundary) == 0 &&
      length(aws_iam_policy.s3_access_boundary) == 0 &&
      length(aws_iam_policy.devcontainer_cache_boundary) == 0 &&
      length(aws_iam_role_policy.ecs_execution) == 1 &&
      length(aws_iam_role_policy.ecs_task) == 1 &&
      length(aws_iam_role_policy.proxy) == 1 &&
      length(aws_iam_role_policy.adot) == 1 &&
      length(aws_iam_role_policy.environment) == 1 &&
      length(aws_iam_role_policy.s3_access) == 1 &&
      length(aws_iam_role_policy.devcontainer_cache_registry_access) == 1 && length(aws_iam_role_policy_attachment.ecs_execution) == 1
    )
    error_message = "Attachment opt-in must manage permissions only, leaving external identities and boundaries untouched."
  }
  assert {
    condition = (
      aws_iam_role_policy.ecs_execution[0].role == "customer-ecs-execution" && data.aws_iam_role.pre_created["ecs_execution"].name == "customer-ecs-execution" &&
      aws_iam_role_policy.ecs_task[0].role == "customer-ecs-task" && data.aws_iam_role.pre_created["ecs_task"].name == "customer-ecs-task" &&
      aws_iam_role_policy.proxy[0].role == "customer-proxy" && data.aws_iam_role.pre_created["proxy"].name == "customer-proxy" &&
      aws_iam_role_policy.adot[0].role == "customer-adot" && data.aws_iam_role.pre_created["adot"].name == "customer-adot" &&
      aws_iam_role_policy.environment[0].role == "customer-environment" && data.aws_iam_role.pre_created["environment"].name == "customer-environment" &&
      aws_iam_role_policy.s3_access[0].role == "customer-s3-access" && data.aws_iam_role.pre_created["s3_access"].name == "customer-s3-access" &&
      aws_iam_role_policy.devcontainer_cache_registry_access[0].role == "customer-devcontainer-cache-registry-access" && data.aws_iam_role.pre_created["devcontainer_cache_registry_access"].name == "customer-devcontainer-cache-registry-access" && aws_iam_role_policy_attachment.ecs_execution[0].role == "customer-ecs-execution" && aws_iam_role_policy_attachment.ecs_execution[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    )
    error_message = "Role paths must be excluded from lookup and attachment names; execution must receive the AWS-managed policy."
  }
  assert {
    condition = (
      length(data.aws_iam_policy_document.s3_access.statement) == 4 && jsondecode(aws_iam_role_policy.devcontainer_cache_registry_access[0].policy) == jsondecode(data.aws_iam_policy_document.devcontainer_cache_registry_access.json) && contains(one(data.aws_iam_policy_document.s3_access_assume.statement).actions, "sts:TagSession") && length(one(data.aws_iam_policy_document.s3_access_assume.statement).condition) == 2
    )
    error_message = "Supplied cache roles must receive the existing policies and retain tag-scoped trust documents."
  }
  assert {
    condition = (
      output.ecs_execution_role_arn == var.pre_created_iam_roles.ecs_execution &&
      output.ecs_task_role_arn == var.pre_created_iam_roles.ecs_task &&
      output.proxy_role_arn == var.pre_created_iam_roles.proxy &&
      output.adot_role_arn == var.pre_created_iam_roles.adot &&
      output.environment_role_arn == var.pre_created_iam_roles.environment &&
      output.s3_access_role_arn == var.pre_created_iam_roles.s3_access &&
      output.devcontainer_cache_registry_access_role_arn == var.pre_created_iam_roles.devcontainer_cache_registry_access
    )
    error_message = "All role outputs must expose the supplied identities."
  }
  assert {
    condition = (
      aws_ecs_task_definition.runner.execution_role_arn == output.ecs_execution_role_arn && aws_ecs_task_definition.proxy[0].execution_role_arn == output.ecs_execution_role_arn && aws_ecs_task_definition.adot.execution_role_arn == output.ecs_execution_role_arn && aws_ecs_task_definition.runner.task_role_arn == output.ecs_task_role_arn && aws_ecs_task_definition.proxy[0].task_role_arn == output.proxy_role_arn && aws_ecs_task_definition.adot.task_role_arn == output.adot_role_arn
    )
    error_message = "All task definitions must use the effective execution and application roles."
  }
  assert {
    condition = (
      jsondecode(local.runner_config).environmentRoleArn == output.environment_role_arn && jsondecode(local.runner_config).instanceProfileName == output.environment_instance_profile_name && jsondecode(local.runner_config).devContainerCacheRegistryAccessRoleArn == output.devcontainer_cache_registry_access_role_arn && one([for env in local.runner_container.environment : env.value if env.name == "S3_ACCESS_ROLE_ARN"]) == output.s3_access_role_arn
    )
    error_message = "Runner configuration and environment variables must use effective roles and profile."
  }
  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.container_registry_bucket.statement : s if s.sid == "DenyReadsExceptS3AccessRole"]).condition == toset([{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = tolist([output.s3_access_role_arn]) }]) && one(one(data.aws_iam_policy_document.dynamodb_resource.statement).condition).values == tolist([output.ecs_task_role_arn])
    )
    error_message = "Resource-policy deny exceptions must recognize the supplied S3 and runner roles."
  }
  assert {
    condition = (
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn]) && one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn])
    )
    error_message = "Both cache trust policies must name the effective runner role."
  }
  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "AssumeRunnerManagedRoles"]) == toset([output.s3_access_role_arn, output.devcontainer_cache_registry_access_role_arn]) && one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "PassEnvironmentRole"]) == toset([output.environment_role_arn]) && one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "PassECSTaskRoles"]) == toset([output.ecs_execution_role_arn, output.ecs_task_role_arn, output.proxy_role_arn])
    )
    error_message = "AssumeRole and PassRole grants must use the selected identities without broadening scopes."
  }
  assert {
    condition = (
      length(aws_iam_instance_profile.environment) == 0 && length(data.aws_iam_instance_profile.environment) == 1 && output.environment_instance_profile_name == "customer-environment-profile"
    )
    error_message = "A supplied profile must be read and reused, never created or modified."
  }
}

run "mixed_ownership_false" {
  command = plan
  variables {
    pre_created_iam_roles = { ecs_task = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-task", attach_iam_policies = false }
  }
  assert {
    condition = (
      length(aws_iam_role.ecs_task) == 0 && length(aws_iam_policy.ecs_task_boundary) == 0 && length(aws_iam_role_policy.ecs_task) == 0 && length(aws_iam_role.ecs_execution) == 1 &&
      length(aws_iam_role.proxy) == 1 &&
      length(aws_iam_role.adot) == 1 &&
      length(aws_iam_role.environment) == 1 &&
      length(aws_iam_role.s3_access) == 1 &&
      length(aws_iam_role.devcontainer_cache_registry_access) == 1 && length(aws_iam_role_policy.ecs_execution) == 1 &&
      length(aws_iam_role_policy.proxy) == 1 &&
      length(aws_iam_role_policy.adot) == 1 &&
      length(aws_iam_role_policy.environment) == 1 &&
      length(aws_iam_role_policy.s3_access) == 1 &&
      length(aws_iam_role_policy.devcontainer_cache_registry_access) == 1
    )
    error_message = "Mixed ownership must independently configure created roles regardless of the attachment flag."
  }
  assert {
    condition = (
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn]) && one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn])
    )
    error_message = "Module-created cache roles must trust the supplied runner role."
  }
}

run "mixed_ownership_true" {
  command = plan
  variables {
    pre_created_iam_roles = { ecs_task = "arn:aws:iam::123456789012:role/customer/platform/customer-ecs-task", attach_iam_policies = true }
  }
  assert {
    condition = (
      length(aws_iam_role.ecs_task) == 0 && length(aws_iam_policy.ecs_task_boundary) == 0 && length(aws_iam_role_policy.ecs_task) == 1 && length(aws_iam_role.ecs_execution) == 1 &&
      length(aws_iam_role.proxy) == 1 &&
      length(aws_iam_role.adot) == 1 &&
      length(aws_iam_role.environment) == 1 &&
      length(aws_iam_role.s3_access) == 1 &&
      length(aws_iam_role.devcontainer_cache_registry_access) == 1 && length(aws_iam_role_policy.ecs_execution) == 1 &&
      length(aws_iam_role_policy.proxy) == 1 &&
      length(aws_iam_role_policy.adot) == 1 &&
      length(aws_iam_role_policy.environment) == 1 &&
      length(aws_iam_role_policy.s3_access) == 1 &&
      length(aws_iam_role_policy.devcontainer_cache_registry_access) == 1
    )
    error_message = "Mixed ownership must independently configure created roles regardless of the attachment flag."
  }
  assert {
    condition = (
      one(one(data.aws_iam_policy_document.s3_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn]) && one(one(data.aws_iam_policy_document.devcontainer_cache_registry_access_assume.statement).principals).identifiers == toset([output.ecs_task_role_arn])
    )
    error_message = "Module-created cache roles must trust the supplied runner role."
  }
}

run "supplied_environment_with_created_profile" {
  command = plan
  variables {
    pre_created_iam_roles = { environment = "arn:aws:iam::123456789012:role/customer/platform/customer-environment" }
  }
  assert {
    condition = (
      length(aws_iam_role.environment) == 0 && length(aws_iam_instance_profile.environment) == 1 && aws_iam_instance_profile.environment[0].role == "customer-environment" && length(data.aws_iam_instance_profile.environment) == 0
    )
    error_message = "A supplied role alone must still receive a module-created profile."
  }
}

run "restricted_ignores_supplied_proxy_false" {
  command = plan
  variables {
    restrict_ingress      = true
    pre_created_iam_roles = { proxy = "not-even-an-arn", attach_iam_policies = false }
  }
  assert {
    condition = (
      length(aws_iam_role.proxy) == 0 && length(aws_iam_role_policy.proxy) == 0 && length(aws_iam_policy.proxy_boundary) == 0 && length(data.aws_iam_role.pre_created) == 0 && output.proxy_role_arn == null
    )
    error_message = "Restricted ingress must ignore the supplied proxy without validation, lookup, policies, or boundaries."
  }
  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "PassECSTaskRoles"]) == toset([output.ecs_task_role_arn, output.ecs_execution_role_arn])
    )
    error_message = "Restricted role passing must omit the proxy."
  }
}

run "restricted_ignores_supplied_proxy_true" {
  command = plan
  variables {
    restrict_ingress      = true
    pre_created_iam_roles = { proxy = "not-even-an-arn", attach_iam_policies = true }
  }
  assert {
    condition = (
      length(aws_iam_role.proxy) == 0 && length(aws_iam_role_policy.proxy) == 0 && length(aws_iam_policy.proxy_boundary) == 0 && length(data.aws_iam_role.pre_created) == 0 && output.proxy_role_arn == null
    )
    error_message = "Restricted ingress must ignore the supplied proxy without validation, lookup, policies, or boundaries."
  }
  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.ecs_task.statement : s.resources if s.sid == "PassECSTaskRoles"]) == toset([output.ecs_task_role_arn, output.ecs_execution_role_arn])
    )
    error_message = "Restricted role passing must omit the proxy."
  }
}

run "reject_invalid_role_arn" {
  command = plan
  variables {
    pre_created_iam_roles = { ecs_task = "not-an-arn" }
  }
  expect_failures = [var.pre_created_iam_roles]
}

run "reject_active_invalid_proxy" {
  command = plan
  variables {
    pre_created_iam_roles = { proxy = "not-an-arn" }
  }
  expect_failures = [data.aws_iam_role.pre_created]
}

run "reject_profile_arn" {
  command = plan
  variables {
    environment_instance_profile_name = "arn:aws:iam::123456789012:instance-profile/customer"
  }
  expect_failures = [var.environment_instance_profile_name]
}

run "reject_profile_without_supplied_role" {
  command = plan
  variables {
    environment_instance_profile_name = "customer-environment-profile"
  }
  expect_failures = [data.aws_iam_instance_profile.environment]
}

run "reject_profile_membership_mismatch" {
  command = plan
  variables {
    pre_created_iam_roles             = { environment = "arn:aws:iam::123456789012:role/customer/platform/customer-environment" }
    environment_instance_profile_name = "customer-environment-profile"
  }
  override_data {
    target          = data.aws_iam_instance_profile.environment
    override_during = plan
    values          = { name = "customer-environment-profile", role_arn = "arn:aws:iam::123456789012:role/different-role" }
  }
  expect_failures = [data.aws_iam_instance_profile.environment]
}

run "reject_role_account_or_path_mismatch" {
  command = plan
  variables {
    pre_created_iam_roles = { ecs_task = "arn:aws:iam::999999999999:role/customer-ecs-task" }
  }
  expect_failures = [data.aws_iam_role.pre_created]
}
