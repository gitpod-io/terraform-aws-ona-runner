#!/usr/bin/env bash
set -euo pipefail

require_pattern() {
  local pattern="$1"
  local file="$2"

  if ! grep -Fq -- "$pattern" "$file"; then
    echo "Missing Fargate parity contract: $pattern in $file" >&2
    exit 1
  fi
}

reject_placeholder() {
  local placeholder="$1"

  if grep -RFn --include='*.tf' -- "$placeholder" .; then
    echo "Unresolved release placeholder: $placeholder" >&2
    exit 1
  fi
}

reject_unsupported_input() {
  local input="$1"

  if grep -Fq -- "variable \"${input}\"" variables.tf; then
    echo "Unsupported CloudFormation configuration input: ${input}" >&2
    exit 1
  fi
}

# This deliberately small source-level fixture protects the released Fargate
# topology until a generated CloudFormation-versus-plan comparison runs in CI.
require_pattern 'requires_compatibilities = ["FARGATE"]' ecs.tf
require_pattern 'resource "aws_ecs_service" "runner"' ecs.tf
require_pattern 'resource "aws_ecs_service" "proxy"' ecs.tf
require_pattern 'resource "aws_ecs_service" "adot"' ecs.tf
require_pattern 'resource "aws_appautoscaling_target" "runner"' ecs.tf
require_pattern 'resource "aws_appautoscaling_target" "proxy"' ecs.tf
require_pattern 'resource "aws_ecs_cluster_capacity_providers" "this"' ecs.tf
require_pattern 'health_check_grace_period_seconds  = 60' ecs.tf
require_pattern 'stopTimeout            = 120' ecs.tf
require_pattern 'dns_record_client_routing_policy = "availability_zone_affinity"' loadbalancer.tf
require_pattern '"ecs:ListServices"' iam.tf
require_pattern 'permissions_boundary = aws_iam_policy.ecs_execution_boundary.arn' iam.tf
require_pattern 'permissions_boundary = aws_iam_policy.ecs_task_boundary.arn' iam.tf
require_pattern 'permissions_boundary = aws_iam_policy.proxy_boundary.arn' iam.tf
require_pattern 'permissions_boundary = aws_iam_policy.adot_boundary.arn' iam.tf
require_pattern 'permissions_boundary = aws_iam_policy.environment_boundary.arn' iam.tf
require_pattern 'permissions_boundary = aws_iam_policy.s3_access_boundary.arn' iam.tf
require_pattern 'permissions_boundary = aws_iam_policy.devcontainer_cache_boundary.arn' iam.tf
require_pattern '{ name = "GITPOD_PRIVATE_ECR_PREFIX", value = local.private_ecr_prefix }' ecs.tf
require_pattern 'private_ecr_prefix' locals.tf
require_pattern 'k5t9d3j5/application/gitpod-next/external/aws-otel-collector:v0.43.3' locals.tf
require_pattern 'k5t9d3j5/application/gitpod-next/external/aws-cli:2.27.22@sha256:1d5753647df57828762601f4d82790f3441060dbc8671cd01c52df05cfd3b2c7' locals.tf
require_pattern 'target_type          = "ip"' loadbalancer.tf
require_pattern '\"runnerTemplateBuildVersion\":' locals.tf
require_pattern '\"gatewayAPIEndpoint\":\"\"' locals.tf

reject_placeholder '__EC2_RUNNER_VERSION__'
reject_placeholder '__GITPOD_PRIVATE_ECR_PREFIX__'

reject_unsupported_input 'gateway_api_endpoint'
reject_unsupported_input 'default_ami'
reject_unsupported_input 'development_version'
reject_unsupported_input 'disable_resource_policies'
reject_unsupported_input 'disable_s3_tls_enforcement'
reject_unsupported_input 'permissions_boundary_arn'

if grep -Fq -- '"defaultAMI"' locals.tf; then
  echo "Unsupported CloudFormation configuration field: defaultAMI" >&2
  exit 1
fi
