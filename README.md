# Ona AWS Runner

This is the Terraform module for the Ona AWS Runner. It deploys an
[Ona](https://ona.com) runner in your AWS VPC, where development environment
resources run in your AWS account.

This module manages native AWS resources directly. It does not wrap the
CloudFormation runner stack, and follows its single supported Fargate
private-ECR installation path.

> AWS Runners require an Enterprise plan.

## Example

The [`runner-with-networking`](./examples/runner-with-networking/) example shows
how to call the module with existing VPC, subnet, DNS, and certificate inputs.

## Release compatibility

The module pins `runner_template_build_version` to one tested stable runner
release, matching the release pinning used by the GCP Terraform module. It
derives the standard runner and proxy images from that version.

| Input | Purpose |
| --- | --- |
| `runner_template_build_version` | Stable release used for the standard images and runner configuration. |
| `runner_image` | Optional custom image with a tag matching the release version. |
| `proxy_image` | Optional custom proxy image with a tag matching the release version. |

The published manifest contains public ECR image references. To match the
CloudFormation private-ECR template, the module maps those references into the
release's regional private ECR mirror, including the mirrored telemetry and
metrics-audit sidecars. Custom private image references remain supported when
both runner images use the same `gitpod/ecr` prefix.

The module returns `release_version`, which is the configured
`runner_template_build_version`. Record it with the Terraform state and verify
it against the release manifest before an upgrade.

The scheduled release workflow checks the published stable manifest and opens
an update pull request when a new stable runner version is available.

## Supported configuration

Terraform accepts the supported CloudFormation runner settings: runner
identity and release tuple, VPC and subnet placement, load balancer visibility
and certificate, custom load-balancer security group, Fargate public IP,
runner size, cache engine, proxy settings, and custom CA trust bundle. It does
not expose CloudFormation-internal or unsupported overrides for the gateway
endpoint, environment AMI, development version, or resource security policies.
Terraform creates the same role-specific permission-boundary classes as the
CloudFormation path for execution, runner, proxy, telemetry, environment, S3,
and devcontainer-cache roles.

The [`custom-domain-client-infra`](./modules/custom-domain-client-infra/) helper
module can create an ACM certificate and Route53 records for customers who want
Terraform to own runner custom-domain DNS resources.

## Resource names

New installations derive AWS resource names from both `runner_name` and the
unique `runner_id`, so multiple runners can use the default name in one account
and region. Upgrading an existing installation without replacing its resources
requires setting `resource_name_prefix` to its previous lowercase
`runner_name`; migrate to the generated prefix in a planned replacement.

## Migration From CloudFormation

For the first release, migrate by creating a new Terraform-managed runner rather
than importing every existing CloudFormation-managed resource. Create the runner
record and environment classes with the Ona Terraform provider, deploy this AWS
module with the new runner ID/token/domain, validate the new runner, then move
workloads to environment classes backed by the new runner.

## Scope

The module implements the supported Fargate runner infrastructure path:

- Three Fargate services for the runner, proxy, and telemetry collector,
  connected with ECS Service Connect and backed by Fargate autoscaling.
- Network Load Balancer with TLS listener and custom domain certificate support.
- S3 buckets for container cache, logs, and agent execution data.
- DynamoDB resources table.
- MemoryDB by default, with ElastiCache as a compatibility cache option.
- Runner configuration and cache connection in SSM Parameter Store.
- Secrets Manager runner token and metrics configuration secrets.
- IAM roles for ECS tasks, ECS instances, environment instances, S3 cache access,
  and devcontainer cache registry access.

See [AWS Runner CloudFormation parity](./docs/parity.md) for the source contract
and the deployment evidence required before release.

## Destroy

`terraform destroy` removes the module\'s log groups and empty S3 buckets.
Empty the cache, logs, and agent buckets first when they contain objects; this
module does not force-delete customer data.
