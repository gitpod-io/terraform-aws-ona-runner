#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Use the shipped resource block so removing its lifecycle guard fails this test.
sed -n '/^resource "aws_service_discovery_service" "internal_runner" {/,/^}/p' "$repo_root/ecs.tf" |
  sed 's/aws_service_discovery_private_dns_namespace.internal_runner\[0\].id/"ns-synthetic"/' > "$test_dir/service.tf"

cat > "$test_dir/main.tf" <<'HCL'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "synthetic"
  secret_key                  = "synthetic"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variable "restrict_ingress" { default = true }
locals { common_tags = {} }
HCL

cat > "$test_dir/terraform.tfstate" <<'JSON'
{
  "version": 4,
  "serial": 1,
  "lineage": "00000000-0000-4000-8000-000000000001",
  "outputs": {},
  "resources": [{
    "mode": "managed",
    "type": "aws_service_discovery_service",
    "name": "internal_runner",
    "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
    "instances": [{
      "index_key": 0,
      "schema_version": 0,
      "attributes": {
        "id": "srv-synthetic",
        "arn": "arn:aws:servicediscovery:us-east-1:123456789012:service/srv-synthetic",
        "name": "runner",
        "description": "",
        "dns_config": [{
          "namespace_id": "ns-synthetic",
          "routing_policy": "MULTIVALUE",
          "dns_records": [{"ttl": 10, "type": "A"}]
        }],
        "health_check_config": [],
        "health_check_custom_config": [{"failure_threshold": 1}],
        "namespace_id": "ns-synthetic",
        "force_destroy": false,
        "tags": {},
        "tags_all": {}
      }
    }]
  }]
}
JSON

for lockfile in "$repo_root/.terraform.lock.hcl" "$repo_root/tests/fixtures/aws6-consumer/.terraform.lock.hcl"; do
  cp "$lockfile" "$test_dir/.terraform.lock.hcl"
  terraform -chdir="$test_dir" init -backend=false -input=false -no-color > "$test_dir/init.log"
  terraform -chdir="$test_dir" plan -refresh=false -input=false -no-color -out=plan.out > "$test_dir/plan.log"
  # AWS 6 adds region metadata to older state; no other change is expected.
  terraform -chdir="$test_dir" show -json plan.out | jq -e '
    [.resource_changes[] | select(.type == "aws_service_discovery_service")] as $services |
    ($services | length) == 1 and
    ($services[0].change | (
      (.actions == ["no-op"] or .actions == ["update"]) and
      (.before | del(.region)) == (.after | del(.region)) and
      .after.health_check_custom_config == [{failure_threshold: 1}]
    ))
  ' || { cat "$test_dir/plan.log" >&2; exit 1; }
  if grep -qi 'deprecated' "$test_dir/plan.log"; then
    cat "$test_dir/plan.log" >&2
    exit 1
  fi
done

echo "Cloud Map custom health checks upgrade without replacement on AWS 5.x and 6.x."
