#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  for version in 5.100.0 6.0.0 6.60.0; do
    bash "$0" "$version"
  done
  exit 0
fi

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 [aws-provider-version]" >&2
  exit 1
fi
aws_version="$1"

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d -t ona-aws-provider.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/source" "$work_dir/selection" "$work_dir/cache"

# Include uncommitted source edits, but never reuse local Terraform state or caches.
git -C "$repo_dir" ls-files -z --cached --others --exclude-standard |
  tar -C "$repo_dir" --null -T - -cf - |
  tar -C "$work_dir/source" -xf -

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE
unset AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
unset AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_AUTHORIZATION_TOKEN AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE
unset TF_DATA_DIR
export AWS_EC2_METADATA_DISABLED=true AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_CONFIG_FILE=/dev/null
export TF_IN_AUTOMATION=true TF_INPUT=false TF_PLUGIN_CACHE_DIR="$work_dir/cache"

# Seed exact, checksum-verified selections without overriding any module constraints.
# Keep random at the repository's locked version while testing each AWS version.
cat > "$work_dir/selection/versions.tf" <<EOF
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "= $aws_version"
    }
    random = {
      source = "hashicorp/random"
      version = "= 3.9.0"
    }
  }
}
EOF
terraform -chdir="$work_dir/selection" init -backend=false

cd "$work_dir/source"
init_and_validate() {
  local directory="$1"
  cp "$work_dir/selection/.terraform.lock.hcl" "$directory/.terraform.lock.hcl"
  terraform -chdir="$directory" init -backend=false
  terraform -chdir="$directory" version -json |
    jq -e --arg version "$aws_version" '.provider_selections["registry.terraform.io/hashicorp/aws"] == $version'
  terraform -chdir="$directory" validate
}

echo "Testing AWS provider $aws_version"
init_and_validate .
terraform test
bash scripts/test-metrics-audit-sync.sh

for module_dir in modules/*/; do
  if [[ -f "${module_dir}/versions.tf" ]]; then
    init_and_validate "$module_dir"
    terraform -chdir="$module_dir" test
  fi
done

for example_dir in examples/*/; do
  if [[ -f "${example_dir}/main.tf" ]]; then
    init_and_validate "$example_dir"
    terraform -chdir="$example_dir" test
  fi
done

bash scripts/test-restricted-runner-settings.sh
bash scripts/test-firewall-config-errors.sh

if [[ "$aws_version" == 6.60.* ]]; then
  init_and_validate tests/fixtures/aws6-consumer
fi

echo "AWS provider $aws_version: all compatibility checks passed"
