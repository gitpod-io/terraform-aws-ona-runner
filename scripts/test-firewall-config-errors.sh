#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module_dir="$repo_root/examples/restricted-runner-with-networking"

# expect_failures in terraform test only catches custom conditions, not native
# file/parser/type errors. Evaluate the same locals without contacting AWS.
expect_error() {
  local fixture="$1" expected="$2" output
  output="$(terraform -chdir="$module_dir" console -no-color \
    -var='aws_region=us-east-1' \
    -var='availability_zones=["us-east-1a","us-east-1b"]' \
    -var='runner_id=019d6999-807b-7e52-ab6f-c9202f13ecf2' \
    -var='runner_token=test-token' \
    -var='routable_vpc_cidr=10.42.0.0/24' \
    -var="firewall_config_path=tests/fixtures/$fixture" \
    <<< 'local.firewall_allowed_domains' 2>&1)" || true
  # console can return zero with error diagnostics and an unknown expression value.
  if [[ "$output" != *"Error:"* || "$output" != *"on firewall.tf"* || "$output" != *"$expected"* ]]; then
    printf 'Unexpected error for %s:\n%s\n' "$fixture" "$output" >&2
    exit 1
  fi
  echo "$fixture: rejected"
}

expect_error does-not-exist.yaml 'no file exists at'
expect_error firewall-malformed.txt 'Call to function "yamldecode" failed'
expect_error firewall-missing-key.yaml 'The given key does not identify an element'
expect_error firewall-missing-role.yaml 'The given key does not identify an element'
expect_error firewall-scalar.yaml 'Inconsistent conditional result types'
expect_error firewall-map.yaml 'Inconsistent conditional result types'
expect_error firewall-null.yaml 'argument must not be null'
