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

# This deliberately small source-level fixture protects the released Fargate
# topology until a generated CloudFormation-versus-plan comparison runs in CI.
require_pattern 'requires_compatibilities = ["FARGATE"]' ecs.tf
require_pattern 'resource "aws_ecs_service" "runner"' ecs.tf
require_pattern 'resource "aws_ecs_service" "proxy"' ecs.tf
require_pattern 'resource "aws_ecs_service" "adot"' ecs.tf
require_pattern 'resource "aws_appautoscaling_target" "runner"' ecs.tf
require_pattern 'resource "aws_appautoscaling_target" "proxy"' ecs.tf
require_pattern '{ name = "GITPOD_PRIVATE_ECR_PREFIX", value = "" }' ecs.tf
require_pattern 'target_type          = "ip"' loadbalancer.tf
require_pattern '\"runnerTemplateBuildVersion\":' locals.tf

reject_placeholder '__EC2_RUNNER_VERSION__'
reject_placeholder '__GITPOD_PRIVATE_ECR_PREFIX__'
