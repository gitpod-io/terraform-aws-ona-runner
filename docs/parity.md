# AWS Runner CloudFormation Parity

This module is a native Terraform implementation of the supported EC2 runner
CloudFormation/CDK path in `gitpod-next/runner/ec2/deploy`.

## Implemented

- ECS cluster with container insights and EC2 launch type.
- Bottlerocket ECS hosts from the AWS SSM public AMI parameter.
- Launch template with IMDSv2, encrypted Bottlerocket volumes, detailed
  monitoring, and ECS image cleanup tuning.
- Auto Scaling Group and ECS capacity provider for the runner task.
- ECS task definition with runner, proxy, Prometheus, node-exporter, and optional
  custom CA init containers.
- Network Load Balancer with TLS listener, ACM certificate, custom-domain proxy
  support, cross-zone load balancing, and internal or internet-facing mode.
- Security groups for ECS tasks, the load balancer, environment instances, and
  cache access.
- S3 buckets for container registry cache, logs, and agent execution data, with
  encryption, public access blocking, and lifecycle expiration.
- DynamoDB resource reconciler table and restrictive resource policy.
- Secrets Manager runner token and metrics configuration secrets.
- SSM runner configuration parameter and AI execution cache connection parameter.
- MemoryDB default cache path and ElastiCache compatibility cache path. The
  Terraform ElastiCache path uses an authenticated TLS replication group so it
  works with the runner's Redis cluster/TLS client behavior.
- IAM roles for ECS execution, ECS task, ECS instances, environment instances,
  S3 cache access, and devcontainer cache registry access.
- Outputs corresponding to the CloudFormation stack outputs needed by operators
  and runner registration flows.

## Intentional First-Release Differences

- Migration is greenfield: deploy a new Terraform-managed runner and move
  environment classes to it. Importing every CloudFormation-created resource is
  intentionally out of scope for the first release.
- The module does not create CloudFormation helper Lambda custom resources. The
  Bottlerocket user data and network/proxy configuration are rendered directly
  by Terraform.
- The module does not create the CloudFormation capacity-provider detach custom
  resource. Terraform owns the ECS capacity provider lifecycle directly.
- Fargate two-service mode and ADOT sidecar mode are not part of the supported
  EC2 runner path targeted by this module.

## Open Parity Checks

- Exercise a real `terraform apply` in an AWS test account and confirm the ECS
  service reaches steady state.
- Confirm runner bootstrap against the current production runner images once the
  image version placeholders are replaced by the release automation.
- Run the IAM permissions audit against `runner/ec2/deploy/pkg/iam` after the
  first AWS test deployment to trim any broader Terraform bootstrap permissions.
