# AWS Runner CloudFormation Parity

This module is a native Terraform implementation of the supported Fargate
runner path defined in `gitpod-next/runner/ec2/deploy`.

## Implemented

- ECS cluster with container insights and Service Connect discovery.
- Separate Fargate services for the runner, proxy, and AWS Distro for
  OpenTelemetry (ADOT) collector.
- Fargate task definitions with read-only root filesystems, CloudWatch log
  groups, health checks, proxy settings, and custom CA initialization.
- Target-tracking autoscaling for the runner and proxy services.
- ADOT target discovery and metrics collection from the runner and proxy.
- Metrics audit files uploaded from the ADOT task to the logs bucket.
- Network Load Balancer with TLS listener, ACM certificate, custom-domain proxy
  support, cross-zone load balancing, and internal or internet-facing mode.
- Optional custom-domain helper module for ACM certificate validation and
  Route53 alias records.
- Security groups for ECS tasks, the load balancer, environment instances, and
  cache access.
- S3 buckets for container registry cache, logs, and agent execution data, with
  encryption, public access blocking, lifecycle expiration, and TLS-only bucket
  policies enabled by default.
- DynamoDB resource reconciler table and restrictive resource policy.
- Secrets Manager runner token and metrics configuration secrets.
- SSM runner configuration parameter and AI execution cache connection parameter.
- MemoryDB default cache path and ElastiCache compatibility cache path. The
  Terraform ElastiCache path uses an authenticated TLS replication group so it
  works with the runner's Redis cluster/TLS client behavior.
- IAM roles for ECS execution, the runner, proxy, ADOT, environment instances,
  S3 cache access, and devcontainer cache registry access.
- Outputs corresponding to the CloudFormation stack outputs needed by operators
  and runner registration flows.

## Intentional First-Release Differences

- Migration is greenfield: deploy a new Terraform-managed runner and move
  environment classes to it. Importing every CloudFormation-created resource is
  intentionally out of scope for the first release.
- The module does not create CloudFormation helper Lambda custom resources.
  Terraform manages the supported AWS resources directly.
- The Fargate path does not create EC2 hosts, Auto Scaling Groups, ECS capacity
  providers, or the capacity-provider detach custom resource.
- The ElastiCache fallback follows the CloudFormation stack's single
  `AWS::ElastiCache::CacheCluster` shape. It uses a non-clustered Redis
  connection while MemoryDB remains the default cache engine.
- Operators must supply the four release compatibility inputs from one tested
  runner release manifest until Terraform module release automation is
  available.

## Open Parity Checks

- Exercise a real `terraform apply` in an AWS test account and confirm all three
  ECS services reach steady state.
- Enable metrics auditing and confirm rotated ADOT files reach the logs bucket
  when proxy and custom CA settings are configured.
- Confirm runner bootstrap using a published runner release tuple.
- Run the IAM permissions audit against `runner/ec2/deploy/pkg/iam` after the
  first AWS test deployment to trim any broader Terraform bootstrap permissions.
