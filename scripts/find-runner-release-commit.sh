#!/usr/bin/env bash
set -euo pipefail

runner_version="${1:-}"
main_ref="${2:-origin/main}"

if [[ ! "$runner_version" =~ ^[0-9]{8}\.[0-9]+$ ]]; then
  echo "Runner version must match YYYYMMDD.N, got: ${runner_version:-<empty>}" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "${main_ref}^{commit}" >/dev/null; then
  echo "Main ref does not identify a commit: $main_ref" >&2
  exit 1
fi

while IFS= read -r commit; do
  if ! variables="$(git show "${commit}:variables.tf" 2>/dev/null)"; then
    continue
  fi
  pinned_runner_version="$(
    awk '
      /^variable "runner_template_build_version"/ { in_variable = 1; next }
      in_variable && $1 == "default" { gsub(/"/, "", $3); print $3; exit }
      in_variable && /^}/ { exit }
    ' <<< "$variables"
  )"
  if [[ "$pinned_runner_version" == "$runner_version" ]]; then
    echo "$commit"
    exit 0
  fi
done < <(git log --format=%H "$main_ref")

echo "Could not find a commit in $main_ref pinning EC2 runner $runner_version" >&2
exit 1
