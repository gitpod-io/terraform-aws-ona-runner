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
subnets. For a deployment without inbound runner infrastructure, use the
[`restricted-runner`](./modules/restricted-runner/) module with an existing VPC,
or adapt the self-contained
[`restricted-runner-with-networking`](./examples/restricted-runner-with-networking/)
example. The example creates the VPC and runner egress networking, with optional
AWS Network Firewall and either managed NAT gateways or a customer-provided
Transit Gateway.

## AWS provider compatibility

The modules support AWS provider 5.x and 6.x with their existing minimum versions.
Choose the series in your root configuration: `~> 5.0` stays on 5.x, while
`~> 6.60.0` selects the 6.60 patch series. Existing 5.x lockfiles remain usable.
Before upgrading, select a module release or commit that allows 6.x, follow the
[AWS provider v6 upgrade guide](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-6-upgrade),
and review `terraform init -upgrade` lockfile changes and a live `terraform plan`
before applying. Updates to `main` do not change existing published module tags.

## Restricted ingress

Set `restrict_ingress = true` to opt into restricted inbound network access for
runner and environment infrastructure. Omitting it or setting it to `false`
preserves the standard ingress behavior. The
[`restricted-runner`](./modules/restricted-runner/) module provides a dedicated
interface that always enables this mode and exposes only the root module's
required identity and network-placement inputs. The
[`restricted-runner-with-networking`](./examples/restricted-runner-with-networking/)
example shows the complete restricted deployment composition.

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

### Runner IAM migration

`runner_iam_phase` controls migration from the original runner task role to a
fixed control function and a confined runtime role. It defaults to `legacy`, so
existing installations retain their task definitions, custom image behavior,
and IAM resource addresses until an operator starts the migration. A release is
eligible for a managed phase only when its manifest and versioned public
template provide protocol 1, both image digests, a matching template URL, and a
SHA-256 digest for the unique inline control source. Image digests by themselves
remain a valid legacy release and do not advertise control support.

Existing installations advance one phase per reviewed apply:

1. `legacy` keeps the original role and task definition.
2. `prepare` installs the verified control function, confined role, and immutable
   task baseline while preserving the legacy task-role selection. The apply may
   register a revised legacy task definition and roll the service.
3. `cutover` deploys the immutable baseline. Both task roles retain cache trust
   during task replacement and existing session expiry.
4. `confined` removes runtime trust from the original role and replaces its
   identity policy with an explicit deny. Set `runner_iam_retirement_confirmed`
   only after the old tasks have stopped and their role sessions have expired.

Create a saved plan and run the state-aware transition check before each apply:

```bash
terraform plan -out=runner-iam.tfplan
terraform show -json runner-iam.tfplan >runner-iam-plan.json
bash scripts/check-runner-iam-transition.sh runner-iam-plan.json
```

The checker selects the full resource address automatically when the plan has
one runner. For several runner module instances, select one exactly or validate
all of them deliberately:

```bash
bash scripts/check-runner-iam-transition.sh \
  --address 'module.runner["blue"].terraform_data.runner_iam_phase' \
  runner-iam-plan.json
bash scripts/check-runner-iam-transition.sh --all runner-iam-plan.json
```

For a confirmed new installation with no previous managed resources in that
module instance, select `confined` and pass `--new-install` to the checker. The
checker rejects this shortcut when prior runner resources exist without the
phase marker; those installations must start with `prepare`. Terraform cannot
infer whether resources outside its prior state belong to an untracked
deployment, so the operator must still confirm that choice.

Keep the current phase while rolling back a compatible application release.
Phase reversals and skipped phases are rejected because old role sessions and
tasks cannot be reconstructed safely from Terraform state. Recover a failed
phase by correcting the same phase or advancing after validation. The original
role remains at its stable Terraform address after `confined`, but has no
runtime trust or usable permissions.

Infrastructure fixes require updating the module version and running
`terraform plan` followed by an approved `terraform apply`; updating runner images
alone does not change task-role permissions. Review the plan for IAM updates and
task rollouts.

The selected release origin must be reachable and trusted from both the runner
and the control function. Runner proxy and custom CA settings do not configure
the control function's network path or Node trust store.

Before selecting `prepare`, `cutover`, or `confined` for a runner whose custom CA
resolves to S3, set `custom_ca_s3_object_arn` to that one exact object ARN. This
is required even when `custom_ca_trust_bundle` is itself an S3 object ARN. The
module validates the declared ARN shape and uses it as the confined runner's
only external CA-object grant. Confined initialization fails before the S3
request when the resolved bucket and key do not match the declaration.

PEM and HTTP(S) CA inputs do not need an S3 declaration. The declaration scopes
artifact access; it does not make the object's contents immutable or prove an
indirect CA value before task initialization. The legacy runner, proxy, and
telemetry task roles retain their existing `gitpod-*` bucket limit, so every S3
CA used by those tasks must still use a matching bucket. Bucket policies and
encryption keys may require additional customer-managed access. Remove an
unused declaration to remove its object grant from the confined role.

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

Terraform deletes all objects, versions, and delete markers from the
runner-managed container registry, logs, and agent buckets during
`terraform destroy`.

The [`custom-domain-client-infra`](./modules/custom-domain-client-infra/) helper
module can create an ACM certificate and Route53 records for customers who want
Terraform to own runner-domain DNS resources. The separate
[`management-plane-custom-domain-client-infra`](./modules/management-plane-custom-domain-client-infra/)
module deploys the Network Load Balancer and VPC endpoint needed to access the
Ona management plane through a custom domain.

The [`restricted-runner`](./modules/restricted-runner/) module wraps the root
runner module with restricted ingress enabled and accepts an optional
`runner_name` for AWS resource naming. The networking resources in the
[`restricted-runner-with-networking`](./examples/restricted-runner-with-networking/)
example intentionally remain example-owned so deployments can adapt them to
their egress and inspection policies.

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

`terraform destroy` removes the module's log groups and force-deletes the
runner-managed container registry, logs, and agent buckets with their contents.
