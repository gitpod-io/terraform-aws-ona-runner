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

variable_files=(
  "variables.tf"
  "modules/restricted-runner/variables.tf"
)
staging_dir="$(mktemp -d)"
trap 'rm -rf -- "$staging_dir"' EXIT

for variable_file in "${variable_files[@]}"; do
  staged_file="${staging_dir}/${variable_file}"
  mkdir -p -- "$(dirname -- "$staged_file")"

  if [[ ! -f "$variable_file" ]]; then
    echo "Missing runner variable file: $variable_file" >&2
    exit 1
  fi

  cp -- "$variable_file" "$staged_file"
  if ! VERSION="$version" perl -0pi -e '
    $updates = s/(variable "runner_template_build_version" \{.*?default\s+=\s+")[^"]+(".*?\n\})/$1$ENV{VERSION}$2/s;
    END { exit 1 unless $updates == 1 }
  ' "$staged_file"; then
    echo "Failed to update runner_template_build_version in $variable_file" >&2
    exit 1
  fi
done

for variable_file in "${variable_files[@]}"; do
  cp -- "${staging_dir}/${variable_file}" "$variable_file"
done

echo "$version"
