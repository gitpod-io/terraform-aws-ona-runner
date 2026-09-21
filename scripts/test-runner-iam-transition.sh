#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/check-runner-iam-transition.sh"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

write_plan() {
  local address=$1
  local before=$2
  local after=$3
  local actions=${4:-}
  local existing=${5:-false}
  local unknown=${6:-false}
  local module_address=${address%terraform_data.runner_iam_phase}
  module_address=${module_address%.}

  if [[ -z $actions ]]; then
    if [[ $before == absent ]]; then
      actions=create
    elif [[ $before == "$after" ]]; then
      actions=no-op
    else
      actions=update
    fi
  fi

  jq -n \
    --arg address "$address" --arg module_address "$module_address" \
    --arg before "$before" --arg after "$after" --arg action "$actions" \
    --argjson existing "$existing" --argjson unknown "$unknown" '
      def resource($resource_address; $resource_type; $resource_name): {
        address: $resource_address, mode: "managed", type: $resource_type, name: $resource_name
      };
      ($action | split(",")) as $actions |
      {
        resource_changes: [
          resource($address; "terraform_data"; "runner_iam_phase") + {change: {
            actions: $actions,
            before: (if $before == "absent" then null else {input: $before} end),
            after: (if ($actions | index("delete")) then null else {input: $after} end),
            after_unknown: {input: $unknown}
          }}
        ],
        prior_state: {values: {root_module:
          (if $module_address == "" then {
            resources: (if $existing then [resource("aws_ecs_service.runner"; "aws_ecs_service"; "runner")] else [] end)
          } else {
            resources: [], child_modules: [{address: $module_address,
              resources: (if $existing then [resource(($module_address + ".aws_ecs_service.runner"); "aws_ecs_service"; "runner")] else [] end)
            }]
          } end)
        }}
      }
    ' >"$temp_dir/plan.json"
}

expect_rejected() {
  local label=$1
  shift
  if "$checker" "$@" 2>/dev/null; then
    echo "checker accepted unsafe case: $label" >&2
    exit 1
  fi
}

root=terraform_data.runner_iam_phase
for transition in legacy:legacy legacy:prepare prepare:prepare prepare:cutover cutover:cutover cutover:confined confined:confined; do
  write_plan "$root" "${transition%%:*}" "${transition##*:}"
  "$checker" "$temp_dir/plan.json"
done

for transition in absent:legacy absent:cutover absent:confined legacy:confined prepare:legacy prepare:confined cutover:prepare confined:cutover; do
  write_plan "$root" "${transition%%:*}" "${transition##*:}"
  expect_rejected "$transition" "$temp_dir/plan.json"
done

write_plan "$root" absent prepare
"$checker" "$temp_dir/plan.json"
write_plan "$root" absent confined
"$checker" --new-install "$temp_dir/plan.json"
expect_rejected "unclassified absent to confined" "$temp_dir/plan.json"

write_plan "$root" absent confined "" true
expect_rejected "legacy resources without a phase marker" --new-install "$temp_dir/plan.json"

write_plan "$root" legacy legacy delete
expect_rejected "deletion" "$temp_dir/plan.json"
write_plan "$root" legacy legacy delete,create
expect_rejected "replacement" "$temp_dir/plan.json"
write_plan "$root" legacy prepare "" false true
expect_rejected "unknown phase" "$temp_dir/plan.json"

nested='module.runner.module.runner.terraform_data.runner_iam_phase'
write_plan "$nested" legacy prepare
"$checker" "$temp_dir/plan.json"

indexed='module.runner[0].terraform_data.runner_iam_phase'
write_plan "$indexed" prepare cutover
"$checker" --address "$indexed" "$temp_dir/plan.json"

keyed='module.runner["blue"].terraform_data.runner_iam_phase'
write_plan "$keyed" cutover confined
"$checker" --address "$keyed" "$temp_dir/plan.json"
expect_rejected "partial selector" --address terraform_data.runner_iam_phase "$temp_dir/plan.json"

jq '.resource_changes += [
  (.resource_changes[0] | .address = "module.runner[\"green\"].terraform_data.runner_iam_phase" | .change.before.input = "prepare" | .change.after.input = "cutover")
]' "$temp_dir/plan.json" >"$temp_dir/multiple.json"
expect_rejected "ambiguous multiple instances" "$temp_dir/multiple.json"
"$checker" --address "$keyed" "$temp_dir/multiple.json"
"$checker" --all "$temp_dir/multiple.json"

printf 'runner IAM transition checks passed\n'
