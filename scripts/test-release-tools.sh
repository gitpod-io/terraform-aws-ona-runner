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

notes_root="${test_root}/release-notes"
mkdir -p "${notes_root}/scripts" "${notes_root}/bin"
cp "${repo_root}/scripts/build-release-notes.sh" "${notes_root}/scripts/"
cp "${repo_root}/scripts/validate-release.sh" "${notes_root}/scripts/"
cp "${repo_root}/variables.tf" "$notes_root/"
printf '0.1.0\n' > "${notes_root}/VERSION"

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
)
