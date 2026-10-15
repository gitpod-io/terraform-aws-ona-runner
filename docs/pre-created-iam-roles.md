# Pre-created IAM roles

For a **new runner**, supply some or all of the seven role ARNs through
`pre_created_iam_roles`. Omitted roles are created and fully configured by the
module. Use `null` for omitted roles, rather than an empty string.

```hcl
pre_created_iam_roles = {
  ecs_execution                      = "arn:aws:iam::123456789012:role/customer/execution"
  ecs_task                           = "arn:aws:iam::123456789012:role/customer/runner"
  proxy                              = "arn:aws:iam::123456789012:role/customer/proxy"
  adot                               = "arn:aws:iam::123456789012:role/customer/telemetry"
  environment                        = "arn:aws:iam::123456789012:role/customer/environment"
  s3_access                          = "arn:aws:iam::123456789012:role/customer/s3-cache"
  devcontainer_cache_registry_access = "arn:aws:iam::123456789012:role/customer/ecr-cache"
  attach_iam_policies                 = false
}
```

The roles must exist in the deployment account. Their ARNs and any supplied
instance profile name must be known at plan time. Role paths are supported. Terraform reads each active supplied role
with `iam:GetRole` and verifies its complete ARN, including account and path,
before using it. Both the restricted wrapper and networking examples accept these
inputs. A supplied proxy role is ignored completely when `restrict_ingress` is
true, including ARN validation, lookup, policy attachment, and role passing.

## Permission ownership

| Role input | `attach_iam_policies` | Module ownership |
|---|---|---|
| Omitted | Either value | Role, trust, tags, boundary, and permission policies |
| Supplied | `false` (default) | Uses the role; customer maintains its permission policies |
| Supplied | `true` | Required inline policies and the execution role's AWS-managed policy attachment |
| Proxy with restricted ingress | Either value | No proxy role resources, lookups, or attachments |

For supplied roles, the customer always owns trust policies, tags, and permission
boundaries. Opting in to attachments does not change these properties or replace
existing unrelated policies. Terraform will remove the permission policies it
owns when those resources are destroyed, including policies attached to supplied
roles. The execution role's managed-policy attachment is also Terraform-owned
when attachment is enabled.

The module continues managing its S3 bucket and DynamoDB resource policies. Their
exceptions use the effective roles regardless of the attachment flag. This is
not a switch to disable every IAM-related API call. For example, creating the
environment instance profile still requires IAM writes unless a profile is also
supplied. The restricted networking example separately creates a VPC flow-log
role; that example-owned role is outside this input's scope.

## Policy source of truth

Use the definitions from **the module version you deploy**. The following links
point to the actual policy definitions; they are not separately maintained
policy copies or permission lists. Customer-managed policies must resolve the
same resource references to the runner's actual resources. Broader organization
restrictions and customer-owned boundaries must permit the required operations.

| Role key | Permission policy | Trust policy | Boundary reference |
|---|---|---|---|
| `ecs_execution` | [`ecs_execution`](../iam.tf#L69), plus the [AWS-managed attachment](../iam.tf#L55) | [`ecs_assume_role`](../iam.tf#L1) | [`ecs_execution_boundary_policy`](../permission-boundaries.tf#L166) |
| `ecs_task` | [`ecs_task`](../iam.tf#L99) | [`fargate_task_assume_role`](../iam.tf#L12) | [`ecs_task_boundary_policy`](../permission-boundaries.tf#L202) |
| `proxy` | [`proxy`](../iam.tf#L459) | [`fargate_task_assume_role`](../iam.tf#L12) | [`proxy_boundary_policy`](../permission-boundaries.tf#L225) |
| `adot` | [`adot`](../iam.tf#L489) | [`fargate_task_assume_role`](../iam.tf#L12) | [`adot_boundary_policy`](../permission-boundaries.tf#L244) |
| `environment` | [`environment`](../iam.tf#L540) | [`ec2_assume_role`](../iam.tf#L29) | [`environment_boundary_policy`](../permission-boundaries.tf#L276) |
| `s3_access` | [`s3_access`](../iam.tf#L646) | [`s3_access_assume`](../iam.tf#L616) | [`s3_access_boundary_policy`](../permission-boundaries.tf#L300) |
| `devcontainer_cache_registry_access` | [`devcontainer_cache_registry_access`](../iam.tf#L710) | [`devcontainer_cache_registry_access_assume`](../iam.tf#L692) | [`devcontainer_cache_boundary_policy`](../permission-boundaries.tf#L324) |

The cache trust definitions reference the effective runner task role. Preserve
their session-tag behavior and conditions. Required role tags are defined on the
[module-managed role resources](../iam.tf), including the environment-role marker
on `environment`; the module does not add tags to supplied roles.

When IAM and infrastructure are provisioned by different teams, give the IAM team
the actual resource identifiers referenced by these policy documents. Some bucket,
secret, and parameter ARNs are only available after infrastructure creation. With
attachments disabled, arrange a staged provisioning/bootstrap process so those
policies are installed before the runner starts operating; supplying role ARNs
alone does not configure permissions. There is no separate exported copy of the
permission documents.

## Environment instance profile

An instance profile is a separate IAM resource containing the environment role.
The runner needs both its name and the role ARN.

| Supplied environment role | `environment_instance_profile_name` | Behavior |
|---|---|---|
| No | `null` (default) | Create the role and a profile containing it |
| Yes | `null` | Create a profile containing the supplied role |
| Yes | Existing profile name | Read and reuse the profile; fail if it contains a different role |
| No | Existing profile name | Reject the configuration |

Supply a profile **name**, not an ARN. This input cannot name a new profile or
request replacement of a profile's role. The attachment flag does not control
profile creation or membership.

For customer-owned resources, create the environment role first, then the profile
and its role association, and then deploy the runner. When supplying only a role,
the module creates and populates the profile before placing its name in runner
configuration. The deployer needs `iam:GetInstanceProfile` for a supplied profile.

Likewise, create a customer-owned runner task role before configuring supplied
cache roles to trust it. If the runner task role is module-created, the IAM team
must configure supplied cache-role trust after that role exists and before cache
access is used. Referencing policy outputs and role inputs mutually across whole
modules can introduce Terraform dependency cycles; this interface does not manage
customer-owned trust.

## Outputs and example

All role outputs return the effective ARN, whether supplied or created:
`ecs_execution_role_arn`, `ecs_task_role_arn`, `proxy_role_arn`, `adot_role_arn`,
`environment_role_arn`, `s3_access_role_arn`, and
`devcontainer_cache_registry_access_role_arn`. `proxy_role_arn` is `null` with
restricted ingress. `environment_instance_profile_name` returns the selected
profile name. These outputs are also exposed by the restricted wrapper.

See the [networking example](../examples/runner-with-networking/) and its
[pre-created IAM variable file](../examples/runner-with-networking/pre-created-iam-roles.tfvars.example).
This feature covers fresh deployments; transferring an existing runner's IAM
resources between Terraform and external ownership is outside its scope.
