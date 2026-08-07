#!/usr/bin/env bash
set -euo pipefail

release_sha="${1:-}"
main_ref="${2:-origin/main}"
release_tag="${3:-}"

if [[ ! "$release_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Release SHA must be a full lowercase commit SHA, got: ${release_sha:-<empty>}" >&2
  exit 1
fi

if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tag must be a semantic version with a v prefix, got: ${release_tag:-<empty>}" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "${release_sha}^{commit}" >/dev/null; then
  echo "Release SHA does not identify a commit: $release_sha" >&2
  exit 1
fi

release_sha="$(git rev-parse "${release_sha}^{commit}")"
if ! git merge-base --is-ancestor "$release_sha" "$main_ref"; then
  echo "Release commit $release_sha does not belong to $main_ref" >&2
  exit 1
fi

if git rev-parse --verify --quiet "refs/tags/${release_tag}^{commit}" >/dev/null; then
  tag_sha="$(git rev-parse "refs/tags/${release_tag}^{commit}")"
  if [[ "$tag_sha" != "$release_sha" ]]; then
    echo "Release tag $release_tag points to $tag_sha, not validated commit $release_sha" >&2
    exit 1
  fi
fi

printf '%s\n' "$release_sha"
