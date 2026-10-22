# Pre-created IAM roles

`pre_created_iam_roles` is an optional object (default `{}`) of existing IAM role
ARNs for a new runner. Supported keys are `ecs_execution`, `ecs_task`, `proxy`,
`adot`, `environment`, `s3_access`, and `devcontainer_cache_registry_access`.
Omitted or `null` roles are created and fully configured by the module. Supplied
roles must exist in the deployment account and their ARNs must be known at plan
time. The `proxy` value is ignored when `restrict_ingress = true`.

`pre_created_iam_roles.attach_iam_policies` is a boolean (default `false`):

- `false`: the customer manages permission policies on supplied roles.
- `true`: the module manages its required inline policies and the execution role's
  AWS-managed policy attachment on supplied roles.

The flag does not affect module-created roles. Supplied-role trust policies,
tags, and permission boundaries remain customer-owned. The policy definitions in
[iam.tf](../iam.tf) and [permission-boundaries.tf](../permission-boundaries.tf)
are the source of truth for the module version being deployed.
