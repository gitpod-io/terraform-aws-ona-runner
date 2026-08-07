#!/usr/bin/env bash
# Release notes contain literal Markdown backticks that shellcheck mistakes for shell expressions.
# shellcheck disable=SC2016
set -euo pipefail

release_tag="${1:-}"
output_file="${2:-release-body.md}"
release_ref="${3:-$release_tag}"

bash scripts/validate-release.sh "$release_tag" >/dev/null

runner_version="$({
  awk '
    /^variable "runner_template_build_version"/ { in_variable = 1; next }
    in_variable && $1 == "default" { gsub(/"/, "", $3); print $3; exit }
    in_variable && /^}/ { exit }
  ' variables.tf
})"
manifest_url="https://releases.gitpod.io/ec2/releases/${runner_version}/manifest.json"
manifest="$(curl --fail --location --retry 3 --silent --show-error "$manifest_url")"
runner_image="$(jq -er '.image' <<<"$manifest")"
proxy_image="$(jq -er '.proxy_image' <<<"$manifest")"
template_url="$(jq -er '.cloudformation_template_url' <<<"$manifest")"
release_notes_anchor="${runner_version//./-}"

previous_tag=""
while IFS= read -r candidate; do
  if [[ "$candidate" != "$release_tag" && "$candidate" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    previous_tag="$candidate"
    break
  fi
done < <(git tag --merged "$release_ref" --sort=-version:refname)

if [[ -n "$previous_tag" ]]; then
  change_range="${previous_tag}..${release_ref}"
else
  change_range="$release_ref"
fi

changelog="$(git log --no-merges --pretty=format:'- %s (`%h`)' "$change_range" \
  --grep='^chore: update stable runner release to ' --invert-grep)"
if [[ -z "$changelog" ]]; then
  changelog="- No user-facing module changes in this release."
fi

infrastructure_paths=(
  ':(glob)*.tf'
  ':(glob)modules/**/*.tf'
)
security_paths=(
  'iam.tf'
  'permission-boundaries.tf'
  'security-groups.tf'
  'secrets.tf'
  's3.tf'
  'dynamo.tf'
  ':(glob)modules/**/iam*.tf'
  ':(glob)modules/**/permission-boundaries*.tf'
  ':(glob)modules/**/security-groups*.tf'
  ':(glob)modules/**/secrets*.tf'
  ':(glob)modules/**/s3*.tf'
  ':(glob)modules/**/dynamo*.tf'
)
infrastructure_changes=""
security_changes=""
if [[ -n "$previous_tag" ]] && ! git diff --quiet "$change_range" -- "${infrastructure_paths[@]}"; then
  infrastructure_changes="$(git log --no-merges --pretty=format:'- %s (`%h`)' "$change_range" -- "${infrastructure_paths[@]}")"
fi
if [[ -n "$previous_tag" ]] && ! git diff --quiet "$change_range" -- "${security_paths[@]}"; then
  security_changes="$(git log --no-merges --pretty=format:'- %s (`%h`)' "$change_range" -- "${security_paths[@]}")"
fi

{
  printf 'This module release pins EC2 runner `%s`, matching the supported CloudFormation Fargate private-ECR release.\n\n' "$runner_version"
  printf 'For application changes in the runner itself, see the [AWS runner release notes](https://ona.com/docs/release-notes/aws-runner#%s).\n\n' "$release_notes_anchor"
  printf '## Runner artifacts\n\n'
  printf '| Component | Artifact |\n'
  printf '| --- | --- |\n'
  printf '| Runner | `%s` |\n' "$runner_image"
  printf '| Proxy | `%s` |\n' "$proxy_image"
  printf '| CloudFormation reference | [%s](%s) |\n\n' "$runner_version" "$template_url"

  if [[ -z "$previous_tag" ]]; then
    printf '## IAM and security configuration\n\n'
    printf 'This is the initial module release. Review the IAM roles, permission boundaries, bucket policies, secrets, and security groups before deployment.\n\n'
  else
    if [[ -n "$infrastructure_changes" ]]; then
      printf '## Infrastructure configuration changes\n\n'
      printf 'This release changes Terraform infrastructure. Review these commits before upgrading:\n\n'
      printf '%s\n\n' "$infrastructure_changes"
    fi

    if [[ -n "$security_changes" ]]; then
      printf '## IAM and security configuration changes\n\n'
      printf 'This release changes IAM permissions or security-sensitive resources. Review these commits before upgrading:\n\n'
      printf '%s\n\n' "$security_changes"
    fi
  fi

  printf '## Terraform module changes\n\n'
  printf '%s\n' "$changelog"
} > "$output_file"
