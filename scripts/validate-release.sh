#!/usr/bin/env bash
set -euo pipefail

release_tag="${1:-}"
module_version="$(tr -d '[:space:]' < VERSION)"

if [[ ! "$module_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must contain a semantic version without a v prefix, got: ${module_version}" >&2
  exit 1
fi

if [[ "$release_tag" != "v${module_version}" ]]; then
  echo "Release tag must be v${module_version}, got: ${release_tag:-<empty>}" >&2
  exit 1
fi

runner_version="$({
  awk '
    /^variable "runner_template_build_version"/ { in_variable = 1; next }
    in_variable && $1 == "default" { gsub(/"/, "", $3); print $3; exit }
    in_variable && /^}/ { exit }
  ' variables.tf
})"

if [[ ! "$runner_version" =~ ^[0-9]{8}\.[0-9]+$ ]]; then
  echo "Unable to read a valid runner_template_build_version from variables.tf" >&2
  exit 1
fi

manifest_url="https://releases.gitpod.io/ec2/releases/${runner_version}/manifest.json"
manifest="$(curl --fail --location --retry 3 --silent --show-error "$manifest_url")"

manifest_version="$(jq -er '.version' <<<"$manifest")"
runner_image="$(jq -er '.image' <<<"$manifest")"
proxy_image="$(jq -er '.proxy_image' <<<"$manifest")"
template_url="$(jq -er '.cloudformation_template_url' <<<"$manifest")"

public_prefix="public.ecr.aws/k5t9d3j5/application/gitpod-next"
expected_runner_image="${public_prefix}/gitpod-ec2-runner:${runner_version}"
expected_proxy_image="${public_prefix}/gitpod-proxy:${runner_version}"
expected_template_url="https://releases.gitpod.io/ec2/releases/${runner_version}/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"

if [[ "$manifest_version" != "$runner_version" ]]; then
  echo "Release manifest version ${manifest_version} does not match module runner version ${runner_version}" >&2
  exit 1
fi

if [[ "$runner_image" != "$expected_runner_image" || "$proxy_image" != "$expected_proxy_image" ]]; then
  echo "Release manifest images do not match the module's supported repositories" >&2
  exit 1
fi

if [[ "$template_url" != "$expected_template_url" ]]; then
  echo "Release manifest does not reference the supported private-ECR Fargate template" >&2
  exit 1
fi

echo "Validated Terraform module ${release_tag} with EC2 runner ${runner_version}"
