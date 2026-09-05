#!/usr/bin/env bash
set -euo pipefail

release_tag="${1:-}"
if [[ ! "$release_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Release tag must be a semantic version with a v prefix, got: ${release_tag:-<empty>}" >&2
  exit 1
fi

released_version="${release_tag#v}"
IFS=. read -r major minor patch <<< "$released_version"
next_version="${major}.${minor}.$((patch + 1))"
current_version="$(tr -d '[:space:]' < VERSION)"

if [[ "$current_version" == "$next_version" ]]; then
  echo "$next_version"
  exit 0
fi

if [[ "$current_version" != "$released_version" ]]; then
  echo "Expected VERSION $released_version or $next_version, got: $current_version" >&2
  exit 1
fi

printf '%s\n' "$next_version" > VERSION
echo "$next_version"
