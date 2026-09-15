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
# Exercise the real group mapping, resources, and moves with synthetic membership ARNs.
awk '
  /^  firewall_rule_groups =/ { print "locals {"; copying = 1 }
  /^resource "aws_networkfirewall_container_association"/ { copying = 0 }
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
      .values.firewall_policy[0].enable_tls_session_holding = false
    else . end
  ]
' "$test_dir/fresh.json" > "$test_dir/resources.json"

write_state() {
  local scenario="$1" cbd="${2:-false}"
  jq --arg scenario "$scenario" --argjson cbd "$cbd" '
    def references:
      map({priority: (if .index == 0 or .index == "runner" then 100 else 200 end),
        resource_arn: .values.arn, deep_threat_inspection: "DISABLED", override: []});
    [.[] | select(.type == "aws_networkfirewall_rule_group")] as $groups |
    (.[] | select(.type == "aws_networkfirewall_firewall_policy")) as $policy |
    ($groups | map(
      .index = (if .index == 0 then "runner" else "environment" end) |
      .cbd = $cbd |
      if .index == "runner" then
        .values.name = "test-migration-runner-domains" |
        .values.arn |= sub("allowed-domains$"; "runner-domains") |
        .values.id = .values.arn
      else . end
    )) as $named |
    ($groups[0] |
      .values.description = "HTTPS domains allowed from Ona runner subnets." |
      .values.rule_group[0].reference_sets = [] |
      .values.rule_group[0].rules_source = [{
        rules_string: null, stateful_rule: [], stateless_rules_and_custom_actions: [],
        rules_source_list: [{generated_rules_type: "ALLOWLIST", target_types: ["TLS_SNI"], targets: ["example.com"]}]
      }]
    ) as $legacy |
    (if $scenario == "legacy" then {groups: [$legacy], attached: [$legacy]}
     elif $scenario == "legacy-empty" then {groups: [], attached: []}
     elif $scenario == "partial" then {groups: [$legacy] + $named, attached: [$legacy]}
     elif $scenario == "partial-switched" then {groups: [$legacy] + $named, attached: $named}
     elif $scenario == "named" then {groups: $named, attached: $named}
     else {groups: $groups, attached: $groups} end) as $state |
    ($policy | .values.firewall_policy[0].stateful_rule_group_reference = ($state.attached | references) |
      if $scenario == "legacy-empty" then
        .values.firewall_policy[0].stateful_default_actions = ["aws:alert_strict", "aws:drop_strict"]
      else . end
    ) as $attached_policy |
    ($state.groups + [$attached_policy]) | group_by([.type, .name]) |
    {version: 4, serial: 1, lineage: "67f1687d-636c-4314-a924-967e4d0754cb", outputs: {}, resources: [
      .[] | {mode: "managed", type: .[0].type, name: .[0].name,
        provider: "provider[\"registry.terraform.io/hashicorp/aws\"]",
        instances: [.[] | {index_key: .index, schema_version: 0, attributes: .values,
          create_before_destroy: (.cbd // false),
          dependencies: (if .type == "aws_networkfirewall_firewall_policy" then
            ["aws_networkfirewall_rule_group.allowed_domains"] else [] end)
        }]
      }
    ]}
  ' "$test_dir/resources.json" > "$test_dir/terraform.tfstate"
}

plan() {
  terraform -chdir="$test_dir" plan -refresh=false -input=false -no-color -out=upgrade.plan "$@" > "$test_dir/plan.log"
  terraform -chdir="$test_dir" show -json upgrade.plan > "$test_dir/upgrade.json"
  terraform -chdir="$test_dir" graph -plan=upgrade.plan > "$test_dir/graph.dot"
}

expect_actions() {
  jq -e --argjson expected "$1" '
    [.resource_changes[] | {key: .address, value: .change.actions}] | from_entries == $expected
  ' "$test_dir/upgrade.json" > /dev/null
}

write_state legacy
plan
expect_actions '{
  "aws_networkfirewall_rule_group.allowed_domains[0]": ["update"],
  "aws_networkfirewall_rule_group.allowed_domains[1]": ["create"],
  "aws_networkfirewall_firewall_policy.default[0]": ["update"]
}'
echo 'Legacy upgrade: original group and policy update in place; no deletions.'

# Cover the initial failed apply and a retry after create-before-destroy was added.
for cbd in false true; do
  write_state partial "$cbd"
  plan
  expect_actions '{
    "aws_networkfirewall_rule_group.allowed_domains[0]": ["update"],
    "aws_networkfirewall_rule_group.allowed_domains[1]": ["no-op"],
    "aws_networkfirewall_rule_group.allowed_domains[\"runner\"]": ["delete"],
    "aws_networkfirewall_firewall_policy.default[0]": ["update"]
  }'
  echo "Partial upgrade (create-before-destroy=$cbd): keep the attached legacy group; delete only the unused duplicate."
done

write_state partial-switched true
plan
expect_actions '{
  "aws_networkfirewall_rule_group.allowed_domains[0]": ["update"],
  "aws_networkfirewall_rule_group.allowed_domains[1]": ["no-op"],
  "aws_networkfirewall_rule_group.allowed_domains[\"runner\"]": ["delete"],
  "aws_networkfirewall_firewall_policy.default[0]": ["update"]
}'
# DOT arrows point from an operation to its prerequisite, not execution order.
grep -E 'allowed_domains.*runner.*destroy.* -> .*firewall_policy.default\[0\]"' "$test_dir/graph.dot" > /dev/null
echo 'Recovered partial upgrade: switch policy back before deleting the duplicate runner group.'

write_state named
plan
expect_actions '{
  "aws_networkfirewall_rule_group.allowed_domains[0]": ["create", "delete"],
  "aws_networkfirewall_rule_group.allowed_domains[1]": ["no-op"],
  "aws_networkfirewall_firewall_policy.default[0]": ["update"]
}'
grep -E 'allowed_domains\[0\].*destroy deposed.* -> .*firewall_policy.default\[0\]"' "$test_dir/graph.dot" > /dev/null
echo 'Earlier role-based deployment: replace runner group only after switching policy; preserve environment group.'

write_state current
plan
expect_actions '{
  "aws_networkfirewall_rule_group.allowed_domains[0]": ["no-op"],
  "aws_networkfirewall_rule_group.allowed_domains[1]": ["no-op"],
  "aws_networkfirewall_firewall_policy.default[0]": ["no-op"]
}'
echo 'Current deployment: no changes.'

for scenario in legacy legacy-empty current; do
  write_state "$scenario"
  plan -var='runner_domains=[]' -var='environment_domains=[]'
  jq -e '
    all(.resource_changes[]; (.change.actions | index("delete")) == null) and
    all(.planned_values.root_module.resources[] | select(.type == "aws_networkfirewall_rule_group");
      .values.rule_group[0].rules_source[0].rules_string | startswith("drop ip @SOURCE_IPS "))
  ' "$test_dir/upgrade.json" > /dev/null
  echo "Empty allowlists ($scenario): deny-only groups, no deletions."
done

# Removing lifecycle ordering must make the earlier role-based replacement unsafe.
sed -i '/create_before_destroy = true/d' "$test_dir/firewall.tf"
write_state named
plan
jq -e 'any(.resource_changes[];
  .address == "aws_networkfirewall_rule_group.allowed_domains[0]" and .change.actions == ["delete", "create"]
)' "$test_dir/upgrade.json" > /dev/null
echo 'Negative control: missing lifecycle restores destroy-before-create replacement.'
