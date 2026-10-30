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

  printf '01.2.3\n' > VERSION
  expect_failure "a version with a leading zero" \
    bash scripts/validate-release.sh v01.2.3

  printf 'not-a-version\n' > VERSION
  expect_failure "a malformed VERSION file" \
    bash scripts/validate-release.sh v0.1.0

  printf '0.1.0-beta.1\n' > VERSION
  expect_failure "a prerelease suffix in VERSION" \
    bash scripts/validate-release.sh v0.1.0-beta.1
)

update_root="${test_root}/runner-update"
mkdir -p "${update_root}/scripts" "${update_root}/bin"
cp "${repo_root}/scripts/update-runner-release.sh" "${update_root}/scripts/"
cp "${repo_root}/variables.tf" "$update_root/"

cat > "${update_root}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

manifest_url="${*: -1}"
if [[ "$manifest_url" != "https://releases.gitpod.io/ec2/releases/20260901.123/manifest.json" ]]; then
  echo "Unexpected manifest URL: $manifest_url" >&2
  exit 1
fi

cat <<'JSON'
{
  "version": "20260901.123",
  "image": "public.ecr.aws/k5t9d3j5/application/gitpod-next/gitpod-ec2-runner:20260901.123",
  "proxy_image": "public.ecr.aws/k5t9d3j5/application/gitpod-next/gitpod-proxy:20260901.123",
  "cloudformation_template_url": "https://releases.gitpod.io/ec2/releases/20260901.123/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"
}
JSON
EOF
chmod +x "${update_root}/bin/curl"

(
  cd "$update_root"

  expect_failure "an omitted runner version" \
    bash scripts/update-runner-release.sh

  updated_version="$(PATH="${update_root}/bin:$PATH" bash scripts/update-runner-release.sh \
    "20260901.123")"
  if [[ "$updated_version" != "20260901.123" ]]; then
    echo "Unexpected updated runner version: $updated_version" >&2
    exit 1
  fi

  grep -Fq 'default     = "20260901.123"' variables.tf
)

target_repo="${test_root}/target-repo"
git init --quiet "$target_repo"
(
  cd "$target_repo"
  git config user.name "Release Test"
  git config user.email "release-test@example.com"

  printf 'release candidate\n' > module.tf
  git add module.tf
  git commit --quiet -m "initial commit"

  printf '0.1.0\n' > VERSION
  cat > variables.tf <<'EOF'
variable "runner_template_build_version" {
  default = "20260901.123"
}
EOF
  git add VERSION variables.tf
  git commit --quiet -m "release candidate"
  main_sha="$(git rev-parse HEAD)"

  actual_sha="$(bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" HEAD v0.1.0)"
  if [[ "$actual_sha" != "$main_sha" ]]; then
    echo "Validated release SHA $actual_sha does not match $main_sha" >&2
    exit 1
  fi

  for tag in v0.1.0-beta.0 v0.1.0-beta.1 v0.1.0-beta.12; do
    test "$(bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" HEAD "$tag")" = "$main_sha"
  done

  for tag in v0.1.0-beta v0.1.0-beta.01 v0.1.0-beta.x v0.1.0-beta.1.extra v0.1.0-rc.1 v01.1.0-beta.1; do
    expect_failure "invalid release tag $tag" \
      bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" HEAD "$tag"
  done

  expect_failure "a shortened release SHA" \
    bash "${repo_root}/scripts/validate-release-target.sh" "${main_sha:0:12}" HEAD v0.1.0

  expect_failure "a release tag with a leading zero" \
    bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" HEAD v01.2.3

  empty_tree="$(git mktree </dev/null)"
  unrelated_sha="$(printf 'unrelated commit\n' | git commit-tree "$empty_tree")"
  expect_failure "a release commit outside main" \
    bash "${repo_root}/scripts/validate-release-target.sh" "$unrelated_sha" "$main_sha" v0.1.0

  expect_failure "a beta commit outside main" \
    bash "${repo_root}/scripts/validate-release-target.sh" "$unrelated_sha" "$main_sha" v0.1.0-beta.1

  git tag v0.1.0-beta.1 "$main_sha"
  bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" HEAD v0.1.0-beta.1 >/dev/null
  git tag v0.1.0-beta.2 "$unrelated_sha"
  expect_failure "an existing beta tag on a different commit" \
    bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" HEAD v0.1.0-beta.2

  git tag v0.1.0 "$unrelated_sha"
  expect_failure "an existing tag on a different commit" \
    bash "${repo_root}/scripts/validate-release-target.sh" "$main_sha" "$main_sha" v0.1.0

  printf 'release metadata\n' >> module.tf
  git add module.tf
  git commit --quiet -m "add release metadata"
  release_sha="$(git rev-parse HEAD)"

  found_sha="$(bash "${repo_root}/scripts/find-runner-release-commit.sh" 20260901.123 HEAD)"
  if [[ "$found_sha" != "$release_sha" ]]; then
    echo "Found runner release commit $found_sha does not match $release_sha" >&2
    exit 1
  fi

  expect_failure "an unknown runner release" \
    bash "${repo_root}/scripts/find-runner-release-commit.sh" 20260909.999 HEAD

  next_version="$(bash "${repo_root}/scripts/advance-module-version.sh" v0.1.0)"
  if [[ "$next_version" != "0.1.1" ]] || [[ "$(tr -d '[:space:]' < VERSION)" != "0.1.1" ]]; then
    echo "Module version did not advance to 0.1.1" >&2
    exit 1
  fi

  next_version="$(bash "${repo_root}/scripts/advance-module-version.sh" v0.1.0)"
  if [[ "$next_version" != "0.1.1" ]]; then
    echo "Repeated module version advance was not idempotent" >&2
    exit 1
  fi

  expect_failure "advancing from an unrelated module version" \
    bash "${repo_root}/scripts/advance-module-version.sh" v0.2.0
)

notes_root="${test_root}/release-notes"
mkdir -p "${notes_root}/scripts" "${notes_root}/bin"
cp "${repo_root}/scripts/build-release-notes.sh" "${notes_root}/scripts/"
cp "${repo_root}/scripts/validate-release.sh" "${notes_root}/scripts/"
printf '0.1.0\n' > "${notes_root}/VERSION"

cat > "${notes_root}/variables.tf" <<'EOF'
variable "runner_template_build_version" {
  default = "20260805.559"
}
EOF

cat > "${notes_root}/bin/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{
  "version": "20260805.559",
  "image": "public.ecr.aws/k5t9d3j5/application/gitpod-next/gitpod-ec2-runner:20260805.559",
  "proxy_image": "public.ecr.aws/k5t9d3j5/application/gitpod-next/gitpod-proxy:20260805.559",
  "cloudformation_template_url": "https://releases.gitpod.io/ec2/releases/20260805.559/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"
}
JSON
EOF
chmod +x "${notes_root}/bin/curl"

(
  cd "$notes_root"
  git init --quiet
  git config user.name "Release Test"
  git config user.email "release-test@example.com"
  git add .
  git commit --quiet -m "initial release"
  git tag v0.1.0

  printf '0.2.0\n' > VERSION
  printf 'resource "aws_elasticache_cluster" "example" {}\n' > cache.tf
  git add VERSION cache.tf
  git commit --quiet -m "feat: adjust cache configuration"
  git tag v0.2.0-beta.1

  printf 'data "aws_iam_policy_document" "example" {}\n' > iam.tf
  git add iam.tf
  git commit --quiet -m "fix: tighten runner permissions"

  PATH="${notes_root}/bin:$PATH" bash scripts/build-release-notes.sh v0.2.0 release-body.md HEAD

  grep -Fq 'AWS runner release notes](https://ona.com/docs/release-notes/aws-runner#20260805-559)' release-body.md
  grep -Fq '## Infrastructure configuration changes' release-body.md
  grep -Fq -- '- feat: adjust cache configuration' release-body.md
  grep -Fq '## IAM and security configuration changes' release-body.md
  grep -Fq -- '- fix: tighten runner permissions' release-body.md

  security_section="$(sed -n '/^## IAM and security configuration changes$/,/^## Terraform module changes$/p' release-body.md)"
  if grep -Fq 'adjust cache configuration' <<<"$security_section"; then
    echo "General infrastructure changes must not be classified as IAM or security changes" >&2
    exit 1
  fi

  for tag in v0.2.0-beta.0 v0.2.0-beta.2 v0.2.0-beta.12; do
    PATH="${notes_root}/bin:$PATH" bash scripts/build-release-notes.sh "$tag" release-body.md HEAD
    grep -Fq -- '- feat: adjust cache configuration' release-body.md
    grep -Fq -- '- fix: tighten runner permissions' release-body.md
  done

  for tag in v0.2.0-beta v0.2.0-beta.01 v0.2.0-beta.x v0.2.0-beta.1.extra v0.2.0-rc.1 v0.3.0-beta.1 v0x2x0-beta.1; do
    expect_failure "invalid or mismatched beta tag $tag" \
      env PATH="${notes_root}/bin:$PATH" bash scripts/validate-release.sh "$tag"
  done

  # Beta publication must retain the same runner-manifest checks as stable.
  sed -i 's/gitpod-proxy:20260805.559/gitpod-proxy:20260805.560/' bin/curl
  for tag in v0.2.0 v0.2.0-beta.2; do
    expect_failure "mismatched runner manifest for $tag" \
      env PATH="${notes_root}/bin:$PATH" bash scripts/validate-release.sh "$tag"
  done
)

# Execute the actual workflow shell bodies with synthetic Git/GitHub commands.
# No tag, release, commit, or push can reach a remote from these tests.
workflow_root="${test_root}/workflow"
mkdir -p "${workflow_root}/bin" "${workflow_root}/scripts"
cp "${repo_root}/scripts/advance-module-version.sh" "${workflow_root}/scripts/"

workflow_step() {
  awk -v step="$1" '
    $0 == "      - name: " step { in_step = 1; next }
    in_step && /^        run: \|$/ { in_run = 1; next }
    in_run && /^          / { print substr($0, 11); next }
    in_run && /^$/ { print; next }
    in_run { exit }
  ' "${repo_root}/.github/workflows/release.yml"
}
workflow_step "Publish tag and GitHub release" > "${workflow_root}/publish.sh"
workflow_step "Advance module version" > "${workflow_root}/advance.sh"
test -s "${workflow_root}/publish.sh"
test -s "${workflow_root}/advance.sh"

cat > "${workflow_root}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "release view" ]]; then
  [[ "$TEST_RELEASE_EXISTS" == true ]]
else
  [[ "$1 $2" == "release create" ]]
  printf '%s\n' "$@" > "$TEST_GH_ARGS"
fi
EOF

cat > "${workflow_root}/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_GIT_CALLS"
case "$1" in
  rev-parse) [[ "$TEST_TAG_EXISTS" == true ]] ;;
  diff) exit 1 ;;
  fetch|checkout|config|add|commit|push) ;;
  *) echo "Unexpected git invocation: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${workflow_root}/bin/gh" "${workflow_root}/bin/git"

(
  cd "$workflow_root"
  export PATH="${workflow_root}/bin:$PATH"
  export TEST_GH_ARGS="${workflow_root}/gh-args" TEST_GIT_CALLS="${workflow_root}/git-calls"
  export RELEASE_SHA="0123456789abcdef0123456789abcdef01234567"
  export TEST_RELEASE_EXISTS=false TEST_TAG_EXISTS=false

  for RELEASE_TAG in v0.1.0-beta.1 v0.1.0; do
    export RELEASE_TAG
    for TEST_TAG_EXISTS in false true; do
      export TEST_TAG_EXISTS
      rm -f "$TEST_GH_ARGS" "$TEST_GIT_CALLS"
      bash -e publish.sh
      grep -Fxq "$RELEASE_TAG" "$TEST_GH_ARGS"
      grep -Fxq -- '--notes-file' "$TEST_GH_ARGS"
      if [[ "$RELEASE_TAG" == *-beta.* ]]; then
        grep -Fxq -- '--prerelease' "$TEST_GH_ARGS"
        grep -Fxq -- '--latest=false' "$TEST_GH_ARGS"
      elif grep -Eq -- '^--(prerelease|latest=)' "$TEST_GH_ARGS"; then
        echo "Stable release must retain its default release flags" >&2
        exit 1
      fi
      if [[ "$TEST_TAG_EXISTS" == true ]]; then
        grep -Fxq -- '--verify-tag' "$TEST_GH_ARGS"
        if grep -Fxq -- '--target' "$TEST_GH_ARGS"; then
          echo "An existing tag must be verified rather than targeted" >&2
          exit 1
        fi
      else
        grep -Fxq -- '--target' "$TEST_GH_ARGS"
        grep -Fxq "$RELEASE_SHA" "$TEST_GH_ARGS"
      fi
    done

    # An existing release must not issue another create call.
    rm -f "$TEST_GH_ARGS" "$TEST_GIT_CALLS"
    TEST_RELEASE_EXISTS=true bash -e publish.sh
    test ! -e "$TEST_GH_ARGS"
    test ! -e "$TEST_GIT_CALLS"

    printf '0.1.0\n' > VERSION
    bash -e advance.sh
    if [[ "$RELEASE_TAG" == *-beta.* ]]; then
      test "$(cat VERSION)" = 0.1.0
      test ! -e "$TEST_GIT_CALLS"
    else
      test "$(cat VERSION)" = 0.1.1
      grep -Fxq 'push origin HEAD:main' "$TEST_GIT_CALLS"
    fi
  done
)

echo "Release tooling tests passed"
