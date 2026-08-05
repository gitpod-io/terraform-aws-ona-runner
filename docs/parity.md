# AWS Runner CloudFormation Parity

This module is a native Terraform implementation of the supported Fargate runner
CloudFormation/CDK path in `gitpod-next/runner/ec2/deploy`.

## Implemented

- ECS cluster with container insights and Fargate capacity.
- Separate Fargate task definitions and services for the runner, proxy, and
  ADOT collector, with Service Connect and autoscaling.
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
- SSM runner configuration, AI execution cache connection, and ADOT collector
  configuration parameters.
- MemoryDB default cache path and an ElastiCache compatibility cache path.
- IAM roles for ECS execution, runner, proxy, ADOT, environment instances, S3
  cache access, and devcontainer cache registry access.
- Outputs corresponding to the CloudFormation stack outputs needed by operators
  and runner registration flows.

## Intentional First-Release Differences

- Migration is greenfield: deploy a new Terraform-managed runner and move
  environment classes to it. Importing every CloudFormation-created resource is
  intentionally out of scope for the first release.
- The module does not create CloudFormation helper Lambda custom resources.
- The ElastiCache fallback follows the CloudFormation stack's single
  `AWS::ElastiCache::CacheCluster` shape. It uses a non-clustered Redis
  connection while MemoryDB remains the default cache engine.
- Operators must supply the four release compatibility inputs from one tested
  runner release manifest until Terraform module release automation is
  available.
- ElastiCache authentication is not yet proven: the CloudFormation source and
  this module both require an AWS integration test before it can be considered
  production parity. Use the MemoryDB default in the meantime.

## Open Parity Checks

- Exercise a real `terraform apply` in an AWS test account and confirm the ECS
  service reaches steady state.
- Confirm runner bootstrap using a published runner release tuple.
- Run the IAM permissions audit against `runner/ec2/deploy/pkg/iam` after the
  first AWS test deployment to trim any broader Terraform bootstrap permissions.
