# AWS Runner CloudFormation parity

This module implements the supported Fargate private-ECR path generated from
`gitpod-next/runner/ec2/deploy`.

## Source contract

With `restrict_ingress` omitted or false, the Terraform plan matches the
released CloudFormation path for:

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

`tests/parity_matrix.tftest.hcl` and `scripts/check-parity-contract.sh` protect
this contract without requiring an AWS account.

With `restrict_ingress = true`, the runner and ADOT services remain, while the
proxy service, Network Load Balancer, proxy-only security-group rules, proxy IAM
resources, and their autoscaling resources are omitted. The private Cloud Map
service and authenticated internal LLM listener remain available.

## Deployment validation

Before publishing the first module release, deploy it in an AWS test account and
verify:

1. Terraform reaches steady state for all three ECS services.
2. The proxy target group becomes healthy for both internal and public load
   balancers.
3. The runner creates, starts, stops, snapshots, and deletes an environment.
4. A stable runner update updates the runner and proxy services through the
   private-ECR mirror.
5. A metrics configuration change rewrites the ADOT configuration, restarts the
   ADOT service, and uploads rotated audit files to the logs bucket.
6. Both cache-engine options accept runner traffic.
7. A second `terraform plan` after runtime configuration changes reports only
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
