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
  passing, policy attachments, creator-scoped S3 cache sessions, project-scoped
  ECR cache sessions, custom CA reads, environment trust, immutable control
  settings, and fail-closed release metadata validation.
- `scripts/test-metrics-audit-sync.sh` executes the rendered upload command with
  a fake AWS CLI, checking successful cleanup, failed-upload retention, quoted
  filenames, and empty rotations.
- `scripts/check-parity-contract.sh` checks selected source-level contracts.
- `scripts/test-restricted-runner-settings.sh` checks rendered runner and telemetry
  task definitions through both restricted wrappers, including proxy/CA values,
  confined CA scope enforcement, bypass defaults, and the absence of inbound
  proxy resources.

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
- Terraform retains the legacy runtime role at its stable address in
  `confined`, removes its runtime trust, and attaches an explicit deny policy
  so existing state does not require an address-changing migration.
- Runner configuration and Redis connection parameters use `SecureString`.
- Managed runner CA access uses one declared exact S3 object ARN. Legacy,
  proxy, and telemetry task roles retain the released `gitpod-*` bucket limit.
- Runner buckets are force-destroyed, unlike CloudFormation-retained resources.
- Public IP assignment defaults to false.
- Large-runner scaling bounds are 2–16 for both runner and proxy. The published
  `20260825.79` template has runner bounds 1–8 and proxy bounds 2–8. Preserve the
  module's size-dependent bounds rather than reducing them to match that artifact.
- Policy statements enforce the supported runtime contract and least privilege;
  they need not reproduce every broader grant in an older released template.
- Restricted ingress is an opt-in extension and requires compatible runtime
  support; it is not the standard public-ingress CloudFormation path.
- The restricted networking example owns its Network Firewall policy separately
  from the CloudFormation deployment. Its generated policy defaults to the
  reviewed `firewall.yaml` baseline plus caller-supplied domains. A local
  `firewall_config_path` replaces that entire allowlist; an explicitly empty
  YAML list denies all firewall-routed traffic. Upgrading an
  existing empty allowlist enables those baseline destinations; a supplied
  `firewall_policy_arn` continues to replace the generated policy entirely.
  When the allowlist blocks `containers.dev`, a separate rule rejects its
  TCP/443 TLS connections from runner subnets to avoid control-manifest fetch
  timeouts. Explicit hostname allowlisting and empty deny-all YAML policies
  retain their behavior. This remains a Terraform-only network policy change.

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
8. All task init containers accept an S3-hosted custom CA bundle. For managed
   phases, verify the exact object declaration and confirm a missing or
   mismatched declaration fails confined initialization before its S3 request.
9. S3 cache sessions read/write their creator's prefix and cannot access another
   creator's objects or list a foreign prefix. ECR cache sessions use the
   configured runner, a nonempty project, optional creator metadata, and an
   explicit `allow-push` boolean; verify pull and push against the selected
   repository policy and reject foreign runner/project repositories.
10. A second `terraform plan` after runtime configuration changes reports only
   intentional drift.
11. Advance an existing installation through `prepare`, `cutover`, and
    `confined`. Confirm the control function rejects unapproved task changes,
    old tasks and sessions are retired before confinement, and the legacy role
    cannot be assumed afterward.

Before publishing restricted ingress, use a runner release containing the
absent-ingress runtime support and validate a fresh deployment. Verify
environment startup, repository clone with preconfigured credentials, private
LLM requests, workload completion and result publication, diagnostic capture,
runner task rotation, and update without a proxy service. Existing environments
may not trust the private listener certificate and are not an in-place migration
target.

These checks require an AWS account and real runner registration; source-level
tests are not a substitute for them.
