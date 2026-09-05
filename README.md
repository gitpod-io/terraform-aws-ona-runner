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
a standard deployment with an existing VPC and runner and load-balancer
subnets. The [`restricted-networking`](./examples/restricted-networking/)
example creates runner egress VPC networking without load-balancer subnets and
passes its outputs to a restricted runner deployment. It supports optional AWS
Network Firewall and either managed NAT gateways or a customer-provided Transit
Gateway.

## Restricted ingress

Set `restrict_ingress = true` to opt into restricted inbound network access for
runner and environment infrastructure. Omitting it or setting it to `false`
preserves the standard ingress behavior. The
[`restricted-networking`](./examples/restricted-networking/) example shows the
restricted deployment composition.

Restricted ingress omits the ingress proxy service, Network Load Balancer,
load-balancer security group, public runner endpoint, and their IAM and
autoscaling resources. `runner_domain`, `certificate_arn`, and
`load_balancer_subnet_ids` are not required in this mode. Outputs for omitted
load-balancer and proxy resources are `null`.

Restricted ingress creates a private Cloud Map DNS service for the runner
tasks and enables direct HTTPS traffic from environment instances to the
runner's LLM-only listener. The runner stores its generated self-signed
certificate and private key in Secrets Manager, and environment access to the
runner security group is limited to `internal_llm_proxy_port` (default `8089`).
Task rotation updates the Cloud Map records without changing the internal URL.
The selected VPC must have DNS support and DNS hostnames enabled so environment
instances can resolve the private Cloud Map namespace.

This mode does not provide interactive ingress features such as SSH, browser
ports, live logs, support-bundle downloads, agent conversation streaming, or
SCM OAuth callbacks. Use preconfigured SCM credentials and collect required
diagnostics through deployment-specific automation. The internal certificate
is injected when an environment is created, so use this topology for fresh
runners and environments rather than as an in-place migration.

## Release compatibility

Published module versions pin `runner_template_build_version` to one tested
stable runner release, matching the release pinning used by the GCP Terraform
module. The module derives the standard runner and proxy images from that
version.

| Input | Purpose |
| --- | --- |
| `runner_template_build_version` | Release used for the standard images and runner configuration. |
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

Each EC2 `latest` build records its immutable runner version on `main`. Stable
promotion then releases the exact historical module commit containing the
promoted runner version; unreleased candidates are never added to an existing
module tag.

Terraform module versions are published as immutable semantic-version tags and
GitHub releases after the pinned runner version passes the deployment checks in
[`docs/parity.md`](./docs/parity.md). See [`CONTRIBUTING.md`](./CONTRIBUTING.md)
for the release procedure.

Terraform remains authoritative for the runner and proxy task definitions. A
Terraform apply deploys the configured release and task settings, reconciling
any task-definition change made by the runner's runtime updater between applies.

## Supported configuration

Terraform accepts the supported CloudFormation runner settings: runner
identity and release tuple, VPC and subnet placement, load balancer visibility
and certificate, custom load-balancer security group, Fargate public IP,
runner size, cache engine, proxy settings, and custom CA trust bundle. It does
not expose CloudFormation-internal or unsupported overrides for the gateway
endpoint, environment AMI, development version, or resource security policies.
Terraform creates the applicable role-specific permission-boundary classes for
execution, runner, telemetry, environment, S3, and devcontainer-cache roles,
plus the proxy role for standard deployments.

By default, Terraform also manages bucket-level S3 Public Access Block settings
for the container registry, logs, and agent buckets. Set
`manage_s3_bucket_public_access_block = false` only when equivalent protection
is enforced outside this module and an AWS Organizations policy denies
`s3:PutBucketPublicAccessBlock`.

The [`custom-domain-client-infra`](./modules/custom-domain-client-infra/) helper
module can create an ACM certificate and Route53 records for customers who want
Terraform to own runner-domain DNS resources. The separate
[`management-plane-custom-domain-client-infra`](./modules/management-plane-custom-domain-client-infra/)
module deploys the Network Load Balancer and VPC endpoint needed to access the
Ona management plane through a custom domain.

The [`restricted-networking`](./modules/restricted-networking/) helper module
creates the VPC, runner and egress subnets, optional AWS Network Firewall, and
VPC, firewall, and Route 53 Resolver logs used by the restricted networking
example.

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

- Runner and telemetry Fargate services, plus a proxy service for standard
  deployments. Standard services use ECS Service Connect and Fargate autoscaling.
- Network Load Balancer with TLS listener and custom domain certificate support
  for standard deployments.
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
