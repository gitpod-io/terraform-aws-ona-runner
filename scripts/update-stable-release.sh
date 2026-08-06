#!/usr/bin/env bash
set -euo pipefail

manifest_url="${1:-https://releases.gitpod.io/ec2/stable/manifest.json}"
manifest="$(curl --fail --location --retry 3 --silent --show-error "$manifest_url")"

version="$(jq -er '.version' <<<"$manifest")"
runner_image="$(jq -er '.image' <<<"$manifest")"
proxy_image="$(jq -er '.proxy_image' <<<"$manifest")"
template_url="$(jq -er '.cloudformation_template_url' <<<"$manifest")"

if [[ ! "$version" =~ ^[0-9]{8}\.[0-9]+$ ]]; then
  echo "Invalid stable runner version: $version" >&2
  exit 1
fi

public_prefix="public.ecr.aws/k5t9d3j5/application/gitpod-next"
expected_runner_image="${public_prefix}/gitpod-ec2-runner:${version}"
expected_proxy_image="${public_prefix}/gitpod-proxy:${version}"
expected_template_url="https://releases.gitpod.io/ec2/releases/${version}/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"

if [[ "$runner_image" != "$expected_runner_image" || "$proxy_image" != "$expected_proxy_image" ]]; then
  echo "Stable manifest images do not match the supported release repositories" >&2
  exit 1
fi

if [[ "$template_url" != "$expected_template_url" ]]; then
  echo "Stable manifest does not reference the supported private-ECR Fargate template" >&2
  exit 1
fi

VERSION="$version" perl -0pi -e 's/(variable "runner_template_build_version" \{.*?default\s+=\s+")[^"]+(".*?\n\})/$1$ENV{VERSION}$2/s' variables.tf

if ! grep -Fq -- "default     = \"${version}\"" variables.tf; then
  echo "Failed to update runner_template_build_version" >&2
  exit 1
fi

echo "$version"
