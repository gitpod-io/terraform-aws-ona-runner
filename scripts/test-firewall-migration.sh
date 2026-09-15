#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module_dir="$repo_root/examples/restricted-runner-with-networking"
test_dir="$(mktemp -d)"
trap 'if [[ $? != 0 ]]; then cat "$test_dir/plan.log"; fi; rm -rf "$test_dir"' EXIT

cp "$module_dir/versions.tf" "$test_dir/"
awk '/^provider / { copying = /"registry.terraform.io\/hashicorp\/aws"/ } copying { print }' \
  "$module_dir/.terraform.lock.hcl" > "$test_dir/.terraform.lock.hcl"
cp "$repo_root/scripts/fixtures/firewall-migration.tf" "$test_dir/settings.tf"
# Exercise the real resources and migration, with synthetic membership ARNs.
awk '
  /^moved \{/ || /^resource "aws_networkfirewall_rule_group" "allowed_domains"/ { copying = 1 }
  /^resource "aws_networkfirewall_firewall" "this"/ { exit }
  copying { print }
' "$module_dir/firewall.tf" > "$test_dir/firewall.tf"

terraform -chdir="$test_dir" init -backend=false -lockfile=readonly -no-color > "$test_dir/init.log"
terraform -chdir="$test_dir" plan -refresh=false -input=false -no-color -out=fresh.plan > "$test_dir/plan.log"
terraform -chdir="$test_dir" show -json fresh.plan > "$test_dir/fresh.json"

# Build local-only state from provider-planned values; never import or apply AWS resources.
jq '
  def arn:
    "arn:aws:network-firewall:us-east-1:123456789012:" +
    (if .type == "aws_networkfirewall_rule_group" then "stateful-rulegroup/" else "firewall-policy/" end) + .values.name;
  [.planned_values.root_module.resources[] |
    .values += {id: arn, arn: arn, tags: {}, tags_all: {}} |
    if .type == "aws_networkfirewall_firewall_policy" then
      .values.firewall_policy[0].enable_tls_session_holding = false |
      .values.firewall_policy[0].stateful_rule_group_reference = [
        {priority: 100, resource_arn: "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/test-migration-allowed-domains", deep_threat_inspection: "DISABLED", override: []}
      ]
    else . end
  ]
' "$test_dir/fresh.json" > "$test_dir/resources.json"

write_state() {
  local scenario="$1"
  jq --arg scenario "$scenario" '
    . as $resources |
    ($resources[] | select(.type == "aws_networkfirewall_rule_group" and .index == "runner") |
      .index = 0 |
      .values.name = "test-migration-allowed-domains" |
      .values.arn = "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/test-migration-allowed-domains" |
      .values.id = .values.arn |
      .values.rule_group[0].reference_sets = [] |
      .values.rule_group[0].rules_source = [{
        rules_string: null, stateful_rule: [], stateless_rules_and_custom_actions: [],
        rules_source_list: [{generated_rules_type: "ALLOWLIST", target_types: ["TLS_SNI"], targets: ["example.com"]}]
      }]
    ) as $legacy |
    (if $scenario == "upgrade" then
      [$legacy] + [$resources[] | select(.type == "aws_networkfirewall_firewall_policy")]
    else $resources + [$legacy] end) |
    group_by([.type, .name]) |
    {version: 4, serial: 1, lineage: "67f1687d-636c-4314-a924-967e4d0754cb", outputs: {}, resources: [
      .[] | {mode: "managed", type: .[0].type, name: .[0].name,
        provider: "provider[\"registry.terraform.io/hashicorp/aws\"]",
        instances: [.[] | {index_key: .index, schema_version: 0, attributes: .values,
          dependencies: (if .type == "aws_networkfirewall_firewall_policy" then
            ["aws_networkfirewall_rule_group.allowed_domains"] else [] end)
        }]
      }
    ]}
  ' "$test_dir/resources.json" > "$test_dir/terraform.tfstate"
}

plan() {
  terraform -chdir="$test_dir" plan -refresh=false -input=false -no-color -out=upgrade.plan > "$test_dir/plan.log"
  terraform -chdir="$test_dir" show -json upgrade.plan > "$test_dir/upgrade.json"
  terraform -chdir="$test_dir" graph -plan=upgrade.plan > "$test_dir/graph.dot"
}

write_state upgrade
plan
jq -e '
  any(.resource_changes[];
    .address == "aws_networkfirewall_rule_group.allowed_domains[\"runner\"]" and
    .previous_address == "aws_networkfirewall_rule_group.allowed_domains[0]" and
    .change.actions == ["create", "delete"]
  ) and any(.resource_changes[];
    .address == "aws_networkfirewall_firewall_policy.default[0]" and .change.actions == ["update"]
  )
' "$test_dir/upgrade.json" > /dev/null
# DOT arrows point from an operation to its prerequisite, not execution order.
grep -E 'allowed_domains.*runner.*destroy deposed.* -> .*firewall_policy.default\[0\]"' "$test_dir/graph.dot" > /dev/null
echo 'Clean upgrade: policy update precedes legacy group deletion.'

write_state partial
plan
# A failed pre-migration apply can already own the destination address.
grep -F 'Unresolved resource instance address changes' "$test_dir/plan.log" > /dev/null
jq -e 'any(.resource_changes[];
  .address == "aws_networkfirewall_rule_group.allowed_domains[0]" and .change.actions == ["delete"]
)' "$test_dir/upgrade.json" > /dev/null
grep -E 'firewall_policy.default\[0\]" -> .*allowed_domains\[0\] \(destroy\)"' "$test_dir/graph.dot" > /dev/null
echo 'Partial apply: detected occupied migration destination; policy recovery is required.'

# Simulate the documented one-time policy reference switch in synthetic state.
jq '
  [.resources[] | select(.type == "aws_networkfirewall_rule_group") | .instances[] |
    select(.index_key == "runner" or .index_key == "environment") |
    {resource_arn: .attributes.arn, priority: (if .index_key == "runner" then 100 else 200 end), deep_threat_inspection: "DISABLED", override: []}
  ] as $references |
  (.resources[] | select(.type == "aws_networkfirewall_firewall_policy") |
    .instances[0].attributes.firewall_policy[0].stateful_rule_group_reference) = $references
' "$test_dir/terraform.tfstate" > "$test_dir/recovered.tfstate"
mv "$test_dir/recovered.tfstate" "$test_dir/terraform.tfstate"
plan
jq -e '
  [.resource_changes[] | select(.change.actions != ["no-op"]) | {address, actions: .change.actions}] == [
    {address: "aws_networkfirewall_rule_group.allowed_domains[0]", actions: ["delete"]}
  ]
' "$test_dir/upgrade.json" > /dev/null
echo 'Recovered partial apply: only the detached legacy group is deleted.'

# Prove the ordering assertion catches regressions in either part of the fix.
cp "$test_dir/firewall.tf" "$test_dir/fixed.tf.saved"
for mutation in lifecycle move; do
  if [[ "$mutation" == lifecycle ]]; then
    sed '/create_before_destroy = true/d' "$test_dir/fixed.tf.saved" > "$test_dir/firewall.tf"
  else
    sed '/^moved {/,/^}/d' "$test_dir/fixed.tf.saved" > "$test_dir/firewall.tf"
  fi
  write_state upgrade
  plan
  if grep -E 'allowed_domains.*runner.*destroy deposed.* -> .*firewall_policy.default\[0\]"' "$test_dir/graph.dot" > /dev/null; then
    echo "Missing $mutation did not invalidate safe upgrade ordering." >&2
    exit 1
  fi
  jq -e --arg mutation "$mutation" 'any(.resource_changes[];
    if $mutation == "lifecycle" then
      .address == "aws_networkfirewall_rule_group.allowed_domains[\"runner\"]" and .change.actions == ["delete", "create"]
    else
      .address == "aws_networkfirewall_rule_group.allowed_domains[0]" and .change.actions == ["delete"]
    end
  )' "$test_dir/upgrade.json" > /dev/null
  echo "Negative control: missing $mutation restores unsafe ordering."
done
