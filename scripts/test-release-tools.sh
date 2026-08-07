#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

expect_failure() {
  local description="$1"
  shift

  if "$@" >"${test_root}/command.out" 2>&1; then
    echo "Expected failure: $description" >&2
    exit 1
  fi
}

validation_root="${test_root}/validation"
mkdir -p "${validation_root}/scripts"
cp "${repo_root}/scripts/validate-release.sh" "${validation_root}/scripts/"
cp "${repo_root}/VERSION" "${repo_root}/variables.tf" "$validation_root/"

(
  cd "$validation_root"
  expect_failure "a release tag that does not match VERSION" \
    bash scripts/validate-release.sh v9.9.9

  printf 'not-a-version\n' > VERSION
  expect_failure "a malformed VERSION file" \
    bash scripts/validate-release.sh v0.1.0
)

target_repo="${test_root}/target-repo"
git init --quiet "$target_repo"
(
  cd "$target_repo"
  git config user.name "Release Test"
  git config user.email "release-test@example.com"

  printf 'release candidate\n' > module.tf
  git add module.tf
  git commit --quiet -m "release candidate"
  main_sha="$(git rev-parse HEAD)"

  actual_sha="$(bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" HEAD v0.1.0)"
  if [[ "$actual_sha" != "$main_sha" ]]; then
    echo "Validated release SHA $actual_sha does not match $main_sha" >&2
    exit 1
  fi

  expect_failure "a shortened release SHA" \
    bash "${repo_root}/scripts/validate-release-target.sh" "${main_sha:0:12}" HEAD v0.1.0

  empty_tree="$(git mktree </dev/null)"
  unrelated_sha="$(printf 'unrelated commit\n' | git commit-tree "$empty_tree")"
  expect_failure "a release commit outside main" \
    bash "${repo_root}/scripts/validate-release-target.sh" "$unrelated_sha" "$main_sha" v0.1.0

  git tag v0.1.0 "$unrelated_sha"
  expect_failure "an existing tag on a different commit" \
    bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" "$main_sha" v0.1.0
)
