#!/usr/bin/env bash
set -euo pipefail

new_install=false
selector=""
validate_all=false

usage() {
  echo "usage: $0 [--new-install] [--address <full-resource-address> | --all] <terraform-plan.json>" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-install)
      new_install=true
      shift
      ;;
    --address)
      [[ $# -ge 2 && -z $selector && $validate_all == false ]] || usage
      selector=$2
      shift 2
      ;;
    --all)
      [[ -z $selector && $validate_all == false ]] || usage
      validate_all=true
      shift
      ;;
    --*) usage ;;
    *) break ;;
  esac
done

[[ $# -eq 1 ]] || usage
plan_file=$1

mapfile -t candidates < <(jq -r '
  .resource_changes[]? |
  select(.mode == "managed" and .type == "terraform_data" and .name == "runner_iam_phase") |
  .address
' "$plan_file")

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "plan does not contain a terraform_data.runner_iam_phase instance" >&2
  exit 1
fi

selected=()
if [[ -n $selector ]]; then
  if ! printf '%s\n' "${candidates[@]}" | grep -Fxq -- "$selector"; then
    echo "phase resource selector does not exactly match a planned instance: $selector" >&2
    exit 1
  fi
  selected=("$selector")
elif [[ $validate_all == true ]]; then
  selected=("${candidates[@]}")
elif [[ ${#candidates[@]} -eq 1 ]]; then
  selected=("${candidates[0]}")
else
  echo "plan contains multiple runner IAM phase instances; use --address with an exact address or --all" >&2
  printf '  %s\n' "${candidates[@]}" >&2
  exit 1
fi

validate_transition() {
  local address=$1
  local change actions before after before_absent module_address existing_resources

  change=$(jq -ce --arg address "$address" '
    [.resource_changes[] | select(.address == $address and .mode == "managed" and .type == "terraform_data" and .name == "runner_iam_phase")] |
    if length == 1 then .[0] else error("selected phase address is not unique") end
  ' "$plan_file")
  actions=$(jq -c '.change.actions' <<<"$change")

  if [[ $actions == *'"delete"'* ]]; then
    echo "$address must not be deleted or replaced" >&2
    return 1
  fi
  if ! jq -e '.change.actions == ["create"] or .change.actions == ["update"] or .change.actions == ["no-op"]' <<<"$change" >/dev/null; then
    echo "$address has unsupported planned actions: $actions" >&2
    return 1
  fi
  if jq -e '.change.after_unknown.input == true' <<<"$change" >/dev/null; then
    echo "$address has an unknown planned runner IAM phase" >&2
    return 1
  fi

  before_absent=$(jq -r '.change.before == null' <<<"$change")
  before=$(jq -er 'if .change.before == null then "absent" else .change.before.input end' <<<"$change") || {
    echo "$address has a missing or invalid previous runner IAM phase" >&2
    return 1
  }
  after=$(jq -er '.change.after.input' <<<"$change") || {
    echo "$address has a missing or invalid planned runner IAM phase" >&2
    return 1
  }
  if ! [[ $after =~ ^(legacy|prepare|cutover|confined)$ ]] || { [[ $before != absent ]] && ! [[ $before =~ ^(legacy|prepare|cutover|confined)$ ]]; }; then
    echo "$address has an unrecognized runner IAM phase: $before -> $after" >&2
    return 1
  fi

  if [[ $before_absent == true && $actions != '["create"]' ]] || [[ $before_absent == false && $actions == '["create"]' ]]; then
    echo "$address actions do not match its previous state: $actions" >&2
    return 1
  fi

  module_address=${address%terraform_data.runner_iam_phase}
  module_address=${module_address%.}
  existing_resources=$(jq -r --arg module_address "$module_address" '
    def modules: ., ((.child_modules // [])[] | modules);
    [(.prior_state.values.root_module? | modules) |
      select((.address // "") == $module_address) |
      (.resources // [])[] |
      select(.mode == "managed" and (.type != "terraform_data" or .name != "runner_iam_phase"))
    ] | length
  ' "$plan_file")

  if [[ $new_install == true ]]; then
    if [[ $before != absent || $after != confined || $existing_resources -ne 0 ]]; then
      echo "$address is not a new installation; new installations require absent state, no prior managed resources in the module instance, and phase confined" >&2
      return 1
    fi
    return 0
  fi

  case "$before:$after" in
    absent:prepare|legacy:legacy|legacy:prepare|prepare:prepare|prepare:cutover|cutover:cutover|cutover:confined|confined:confined)
      ;;
    *)
      echo "$address runner IAM phase transition $before -> $after is not allowed" >&2
      return 1
      ;;
  esac
}

for address in "${selected[@]}"; do
  validate_transition "$address"
done
