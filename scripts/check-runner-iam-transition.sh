#!/usr/bin/env bash
set -euo pipefail

new_install=false
if [[ ${1:-} == "--new-install" ]]; then
  new_install=true
  shift
fi
if [[ $# -ne 1 ]]; then
  echo "usage: $0 [--new-install] <terraform-plan.json>" >&2
  exit 2
fi

plan_file=$1
change=$(jq -c '.resource_changes[]? | select(.address == "terraform_data.runner_iam_phase")' "$plan_file")
if [[ -z $change ]]; then
  echo "plan does not contain terraform_data.runner_iam_phase" >&2
  exit 1
fi

previous_state_absent=$(jq -r '.change.before == null' <<<"$change")
before=$(jq -r '.change.before.input // "legacy"' <<<"$change")
after=$(jq -r '.change.after.input // empty' <<<"$change")
if [[ -z $after ]]; then
  echo "planned runner IAM phase is missing" >&2
  exit 1
fi

if [[ $new_install == true ]]; then
  if [[ $previous_state_absent != true || $after != confined ]]; then
    echo "new installations must transition from absent state to confined" >&2
    exit 1
  fi
  exit 0
fi

case "$before:$after" in
  legacy:legacy|legacy:prepare|prepare:prepare|prepare:cutover|cutover:cutover|cutover:confined|confined:confined)
    ;;
  *)
    echo "runner IAM phase transition $before -> $after is not allowed" >&2
    exit 1
    ;;
esac
