#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/check-runner-iam-transition.sh"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

write_plan() {
  local before=$1
  local after=$2
  jq -n --arg before "$before" --arg after "$after" '{resource_changes:[{address:"terraform_data.runner_iam_phase",change:{before:(if $before == "absent" then null else {input:$before} end),after:{input:$after}}}]}' >"$temp_dir/plan.json"
}

for transition in legacy:legacy legacy:prepare prepare:prepare prepare:cutover cutover:cutover cutover:confined confined:confined; do
  write_plan "${transition%%:*}" "${transition##*:}"
  "$checker" "$temp_dir/plan.json"
done

for transition in legacy:confined prepare:legacy prepare:confined cutover:prepare confined:cutover; do
  write_plan "${transition%%:*}" "${transition##*:}"
  if "$checker" "$temp_dir/plan.json" 2>/dev/null; then
    echo "checker accepted unsafe transition $transition" >&2
    exit 1
  fi
done

write_plan absent confined
"$checker" --new-install "$temp_dir/plan.json"
if "$checker" "$temp_dir/plan.json" 2>/dev/null; then
  echo "checker accepted an unclassified absent-state confined transition" >&2
  exit 1
fi

write_plan legacy confined
if "$checker" --new-install "$temp_dir/plan.json" 2>/dev/null; then
  echo "checker accepted an existing legacy installation as new" >&2
  exit 1
fi

write_plan absent prepare
"$checker" "$temp_dir/plan.json"
if "$checker" --new-install "$temp_dir/plan.json" 2>/dev/null; then
  echo "checker accepted prepare for a declared new installation" >&2
  exit 1
fi

printf 'runner IAM transition checks passed\n'
