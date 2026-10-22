locals {
  # Use input values for resource counts; supplied ARNs must be known at plan time.
  pre_created_iam_role_arns = {
    ecs_execution                      = var.pre_created_iam_roles.ecs_execution
    ecs_task                           = var.pre_created_iam_roles.ecs_task
    proxy                              = var.restrict_ingress ? null : var.pre_created_iam_roles.proxy
    adot                               = var.pre_created_iam_roles.adot
    environment                        = var.pre_created_iam_roles.environment
    s3_access                          = var.pre_created_iam_roles.s3_access
    devcontainer_cache_registry_access = var.pre_created_iam_roles.devcontainer_cache_registry_access
  }
  create_iam_roles = {
    for name, arn in local.pre_created_iam_role_arns : name =>
    (name == "proxy" && var.restrict_ingress ? false : arn == null)
  }
  attach_iam_role_policies = {
    for name, create in local.create_iam_roles : name =>
    (name == "proxy" && var.restrict_ingress ? false : create || var.pre_created_iam_roles.attach_iam_policies)
  }

  # Keep identities in separate locals: cache-role trust depends on the runner
  # role and must not depend on a map containing the cache roles themselves.
  ecs_execution_role_arn                      = (local.create_iam_roles.ecs_execution ? aws_iam_role.ecs_execution[0].arn : data.aws_iam_role.pre_created["ecs_execution"].arn)
  ecs_task_role_arn                           = (local.create_iam_roles.ecs_task ? aws_iam_role.ecs_task[0].arn : data.aws_iam_role.pre_created["ecs_task"].arn)
  proxy_role_arn                              = var.restrict_ingress ? null : (local.create_iam_roles.proxy ? aws_iam_role.proxy[0].arn : data.aws_iam_role.pre_created["proxy"].arn)
  adot_role_arn                               = (local.create_iam_roles.adot ? aws_iam_role.adot[0].arn : data.aws_iam_role.pre_created["adot"].arn)
  environment_role_arn                        = (local.create_iam_roles.environment ? aws_iam_role.environment[0].arn : data.aws_iam_role.pre_created["environment"].arn)
  s3_access_role_arn                          = (local.create_iam_roles.s3_access ? aws_iam_role.s3_access[0].arn : data.aws_iam_role.pre_created["s3_access"].arn)
  devcontainer_cache_registry_access_role_arn = (local.create_iam_roles.devcontainer_cache_registry_access ? aws_iam_role.devcontainer_cache_registry_access[0].arn : data.aws_iam_role.pre_created["devcontainer_cache_registry_access"].arn)

  # IAM APIs take the role name, excluding its optional path.
  ecs_execution_role_name                      = local.ecs_execution_role_arn == null ? null : reverse(split("/", local.ecs_execution_role_arn))[0]
  ecs_task_role_name                           = local.ecs_task_role_arn == null ? null : reverse(split("/", local.ecs_task_role_arn))[0]
  proxy_role_name                              = local.proxy_role_arn == null ? null : reverse(split("/", local.proxy_role_arn))[0]
  adot_role_name                               = local.adot_role_arn == null ? null : reverse(split("/", local.adot_role_arn))[0]
  environment_role_name                        = local.environment_role_arn == null ? null : reverse(split("/", local.environment_role_arn))[0]
  s3_access_role_name                          = local.s3_access_role_arn == null ? null : reverse(split("/", local.s3_access_role_arn))[0]
  devcontainer_cache_registry_access_role_name = local.devcontainer_cache_registry_access_role_arn == null ? null : reverse(split("/", local.devcontainer_cache_registry_access_role_arn))[0]
  environment_instance_profile_name            = var.environment_instance_profile_name == null ? aws_iam_instance_profile.environment[0].name : data.aws_iam_instance_profile.environment[0].name
}

data "aws_iam_role" "pre_created" {
  for_each = {
    for name, arn in local.pre_created_iam_role_arns : name => arn if arn != null
  }
  name = reverse(split("/", each.value))[0]

  lifecycle {
    precondition {
      condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/([!-~]+/)?[A-Za-z0-9_+=,.@-]{1,64}$", each.value))
      error_message = "Active pre-created roles, including the proxy, must be valid AWS IAM role ARNs."
    }
    postcondition {
      condition     = self.arn == each.value
      error_message = "A pre-created IAM role must match the supplied ARN, including its account and path, in the deployment account."
    }
  }
}

data "aws_iam_instance_profile" "environment" {
  count = var.environment_instance_profile_name == null ? 0 : 1
  name  = var.environment_instance_profile_name

  lifecycle {
    precondition {
      condition     = var.pre_created_iam_roles.environment != null
      error_message = "An existing environment instance profile requires pre_created_iam_roles.environment."
    }
    postcondition {
      condition     = self.role_arn == local.environment_role_arn
      error_message = "The existing environment instance profile must contain the supplied environment role."
    }
  }
}
