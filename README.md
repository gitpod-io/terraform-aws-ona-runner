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

## Release compatibility inputs

The module requires a tested runner release tuple: `runner_image`,
`proxy_image`, and `runner_template_build_version`. Obtain all three values
from the same runner release manifest. The CloudFormation
release process resolves these values while packaging a template; Terraform
release automation has not yet been published, so the module intentionally does
not provide unsafe placeholder defaults.

| Input | Purpose |
| --- | --- |
| `runner_image` | Tested EC2 runner image from the release manifest. |
| `proxy_image` | Tested runner proxy image from that same manifest. |
| `runner_template_build_version` | Version written to the runner configuration. |

`private_ecr_prefix` is optional. Set it only when your installation mirrors
public ECR images into a private ECR registry; leave it empty to use the public
image references from the release manifest.

The module returns `release_version`, which is the configured
`runner_template_build_version`. Record it with the Terraform state and verify
it against the release manifest before an upgrade.

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

See [AWS Runner CloudFormation Parity](./docs/parity.md) for the current parity
map and first-release migration notes.

## Destroy

`terraform destroy` removes the module\'s log groups and empty S3 buckets.
Empty the cache, logs, and agent buckets first when they contain objects; this
module does not force-delete customer data.
