# AWS Runner CloudFormation parity

This module implements the supported Fargate enterprise private-ECR deployment.
Use the public manifest at
`https://releases.gitpod.io/ec2/releases/<runner_template_build_version>/manifest.json`
and its `cloudformation_template_url` as versioned comparison inputs.

## Source contract

With `restrict_ingress` omitted or false, the intended compatibility contract
covers the released CloudFormation path for:

- runner, proxy, and ADOT task definitions and ECS services;
- Service Connect endpoints, logs, and sibling-service discovery permissions;
- task sizing, autoscaling bounds, capacity providers, shutdown timing, and
  load-balancer health timing;
- Network Load Balancer routing, listener, target group, and public or internal
  placement;
- MemoryDB and ElastiCache selection;
- private-ECR runner, proxy, telemetry, and metrics-audit images;
- runner configuration, proxy configuration, and custom CA initialization;
- S3, DynamoDB, Secrets Manager, SSM, security groups, IAM roles, and
  role-specific permission boundaries.

## Regression coverage

These checks run without an AWS account:

- `tests/parity_matrix.tftest.hcl` checks selected topology/configuration properties.
- `tests/iam_permissions.tftest.hcl` uses the real policy-document provider with
  synthetic plan fixtures to check task-role grants, operation scopes, ECS role
  passing, creator-scoped cache sessions, custom CA reads, and environment trust.
- `scripts/test-metrics-audit-sync.sh` executes the rendered upload command with
  a fake AWS CLI, checking successful cleanup, failed-upload retention, quoted
  filenames, and empty rotations.
- `scripts/check-parity-contract.sh` checks selected source-level contracts.

These are regression checks, not a generated comparison of every CloudFormation
property or a complete AWS policy simulator. Do not replace policy assertions
with mocked empty documents. When changing a contract, add coverage that would
fail for the old or incorrectly scoped behavior.

With `restrict_ingress = true`, the runner and ADOT services remain, while the
proxy service, Network Load Balancer, proxy-only security-group rules, proxy IAM
resources, and their autoscaling resources are omitted. The private Cloud Map
service and authenticated internal LLM listener remain available.

## Intentional differences and upgrade review

- Terraform owns resource names, tags, task definitions, and initial service
  desired counts. A plan after runtime updates or autoscaling needs review.
- Runner configuration and Redis connection parameters use `SecureString`.
- Runner buckets are force-destroyed, unlike CloudFormation-retained resources.
- Public IP assignment defaults to false.
- Large-runner scaling bounds are 2–16 for both runner and proxy. The published
  `20260825.79` template has runner bounds 1–8 and proxy bounds 2–8. Preserve the
  module's size-dependent bounds rather than reducing them to match that artifact.
- Policy statements enforce the supported runtime contract and least privilege;
  they need not reproduce every broader grant in an older released template.
- Restricted ingress is an opt-in extension and requires compatible runtime
  support; it is not the standard public-ingress CloudFormation path.

Review counterpart behavior for IAM, ECS/bootstrap commands, networking, storage,
configuration, and release-default changes. Record the reference release,
verification evidence, and any intentional exception in the PR. Private
implementation comparisons require maintainer verification, not private-source
access from public CI.

Apply the updated module to deliver infrastructure changes. A runner image bump
alone cannot update IAM grants or trust. Validate new role sessions after policy
updates; changing role trust does not revoke previously issued sessions.
A reviewed plan should distinguish in-place IAM updates from task rollouts and
unexpected replacements. Retain the exact module commit and runner release with
deployment test evidence.

## Deployment validation

Before publishing the first module release, deploy it in an AWS test account and
verify:

1. Terraform reaches steady state for all three ECS services.
2. The proxy target group becomes healthy for both internal and public load
   balancers.
3. The runner creates, starts, stops, snapshots, and deletes an environment.
4. Enabling a warm pool creates and reconciles its Auto Scaling Group.
5. A stable runner update updates the runner and proxy services through the
   private-ECR mirror.
6. A metrics configuration change rewrites the ADOT configuration, restarts the
   ADOT service, and uploads rotated audit files to the logs bucket.
7. Both cache-engine options accept runner traffic.
8. All task init containers accept an S3-hosted custom CA bundle.
9. Cache sessions read/write their creator's prefix and cannot access another
   creator's objects or list a foreign prefix.
10. A second `terraform plan` after runtime configuration changes reports only
   intentional drift.

Before publishing restricted ingress, use a runner release containing the
absent-ingress runtime support and validate a fresh deployment. Verify
environment startup, repository clone with preconfigured credentials, private
LLM requests, workload completion and result publication, diagnostic capture,
runner task rotation, and update without a proxy service. Existing environments
may not trust the private listener certificate and are not an in-place migration
target.

These checks require an AWS account and real runner registration; source-level
tests are not a substitute for them.
