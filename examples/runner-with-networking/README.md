# Runner with existing networking

This example deploys the standard runner topology into an existing VPC, with a
runner proxy and Network Load Balancer. Copy `terraform.tfvars.example` and
provide the existing runner and load-balancer subnet IDs.

For a restricted runner without ingress infrastructure, use the
[`restricted-runner-with-networking`](../restricted-runner-with-networking/)
example.

## Pre-created IAM roles

This entrypoint accepts `pre_created_iam_roles` and
`environment_instance_profile_name`. See
[the IAM ownership and policy-source documentation](../../docs/pre-created-iam-roles.md).
