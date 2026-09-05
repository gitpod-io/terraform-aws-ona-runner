# Contributing

[![Build with Ona](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/gitpod-io/terraform-aws-ona-runner)

This document provides guidelines for contributing to the Ona AWS Runner
Terraform module.

## Development Environment

The easiest way to get started is to open this repository in [Ona](https://ona.com/)
or run the included [dev container](.devcontainer/) locally with
[VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
or any compatible IDE. The dev container comes pre-configured with the tools
needed to validate and deploy the module.

If you prefer a manual setup, install the following:

- [Terraform](https://terraform.io/) >= 1.7 (required for provider-mocked tests)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [pre-commit](https://pre-commit.com/)
- [terraform-docs](https://github.com/terraform-docs/terraform-docs)

## File Structure

| Path | Description |
|---|---|
| `*.tf` | Root module resources |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |
| `versions.tf` | Provider and Terraform version constraints |
| `examples/` | Example configurations |
| `docs/` | Additional documentation |

## Making Changes

1. Create a feature branch.
2. Make your changes, following the conventions in this repository.
3. Run formatting and validation checks.
4. Submit a pull request against `main`.

### Linting and Formatting

This repository uses [pre-commit](https://pre-commit.com/) hooks for Terraform
formatting, generated documentation, shellcheck, and general file hygiene.
Install the hooks once after cloning:

```bash
pre-commit install
```

To run all checks manually:

```bash
pre-commit run --all-files
```

### Terraform Validation

Run these checks before opening a pull request:

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform test

for module_dir in modules/*/; do
  terraform -chdir="$module_dir" init -backend=false
  terraform -chdir="$module_dir" validate
  terraform -chdir="$module_dir" test
done
```

Validate examples separately:

```bash
for example_dir in examples/*/; do
  (cd "$example_dir" && terraform init -backend=false && terraform validate)
done
```

## Releases

Module releases use semantic versions and immutable Git tags. `VERSION` holds
the module version to publish; runner application versions remain pinned
separately by `runner_template_build_version`.

Every EC2 `latest` release updates `runner_template_build_version` on `main`
from that release's immutable manifest. When an EC2 release is promoted to
`stable`, the promotion workflow finds the module commit containing that exact
runner version and dispatches this repository's release workflow with the
commit SHA and the semantic version from that commit's `VERSION` file. After a
successful module release, the release workflow advances `VERSION` to the next
patch version on `main`.

Before approving the dispatched release:

1. Fetch the dispatched release commit and complete the deployment
   checks in [`docs/parity.md`](docs/parity.md) from that commit in an AWS test
   account:

   ```bash
   git fetch origin
   release_sha="<release-sha>"
   git switch --detach "$release_sha"
   test -z "$(git status --porcelain --untracked-files=all)"
   release_sha="$(git rev-parse HEAD)"
   ```

2. Run the same checks used by CI:

   ```bash
   terraform fmt -check -recursive
   bash scripts/check-parity-contract.sh
   terraform init -backend=false
   terraform validate
   terraform test
   bash scripts/validate-release.sh "v$(tr -d '[:space:]' < VERSION)"
   test "$(git rev-parse HEAD)" = "$release_sha"
   test -z "$(git status --porcelain --untracked-files=all)"
   ```

   The final two checks confirm that the live deployment used the recorded
   commit without tracked or untracked source changes. The repository ignores
   Terraform variable and state files, so these checks bind the module source,
   not the deployment inputs or state.

3. Confirm that `release_sha` and the requested tag in the pending release
   workflow match the deployed commit and its `VERSION`, then approve the
   `terraform-registry-release` environment.

For manual recovery, dispatch the release workflow from `main` with the same
tag and release commit:

```bash
release_tag="<release-tag>"
release_sha="<validated-release-sha>"
gh workflow run release.yml --ref main \
  -f tag="${release_tag}" \
  -f release_sha="${release_sha}"
```

The release workflow verifies that the requested tag matches the release
commit's `VERSION`, the exact release commit belongs to `main`, the immutable
EC2 release manifest is coherent, and all Terraform checks pass. The publish
job then waits for approval through the `terraform-registry-release` GitHub
environment before creating the tag and a GitHub release containing the pinned
runner artifacts, infrastructure and security changes, and module changelog.

Repository administrators must configure the
`terraform-registry-release` environment with required reviewers and prevent
self-approval. Reviewers approve publication only after confirming that the
workflow's `release_sha` is the commit that passed the AWS deployment checks.

If GitHub release publication fails after the tag is created, dispatch the
workflow again with the same tag and release commit SHA. It validates the tagged
commit and completes the missing GitHub release. Never move or replace a
published tag.
