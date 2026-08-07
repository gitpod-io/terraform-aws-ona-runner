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
separately by `runner_template_build_version`. Bump `VERSION` in a pull request
before publishing the next module release.

Before publishing a release:

1. Merge a pull request that sets `VERSION` to the intended module version and
   pins a tested stable EC2 runner release.
2. Fetch `main`, record the exact release commit, and complete the deployment
   checks in [`docs/parity.md`](docs/parity.md) from that commit in an AWS test
   account:

   ```bash
   git fetch origin main
   git switch --detach origin/main
   release_sha="$(git rev-parse HEAD)"
   ```

3. Run the same checks used by CI:

   ```bash
   terraform fmt -check -recursive
   bash scripts/check-parity-contract.sh
   terraform init -backend=false
   terraform validate
   terraform test
   bash scripts/validate-release.sh "v$(tr -d '[:space:]' < VERSION)"
   ```

4. Dispatch the release workflow from `main`. It validates the release commit
   before creating the immutable tag and GitHub release:

   ```bash
   version="$(tr -d '[:space:]' < VERSION)"
   gh workflow run release.yml --ref main \
     -f tag="v${version}" \
     -f release_sha="${release_sha}"
   ```

The release workflow verifies that the requested tag matches `VERSION`, the
exact release commit belongs to `main`, the immutable EC2 release manifest is
coherent, and all Terraform checks pass. The publish job then waits for approval
through the `terraform-registry-release` GitHub environment before creating the
tag and a GitHub release containing the pinned runner artifacts, infrastructure
and security changes, and module changelog.

Before the first release, a repository administrator must configure the
`terraform-registry-release` environment with required reviewers and prevent
self-approval. Reviewers approve publication only after confirming that the
workflow's `release_sha` is the commit that passed the AWS deployment checks.

For the initial release, connect this public repository to the Terraform
Registry after the workflow creates the first tag. The Registry imports that
tag and installs a webhook that discovers later module versions when their
validated tags are created.

If GitHub release publication fails after the tag is created, dispatch the
workflow again with the same tag and release commit SHA. It validates the tagged
commit and completes the missing GitHub release. Never move or replace a
published tag.
