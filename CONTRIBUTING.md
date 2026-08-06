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
2. Complete the deployment checks in [`docs/parity.md`](docs/parity.md) from the
   release commit in an AWS test account.
3. Run the same checks used by CI:

   ```bash
   terraform fmt -check -recursive
   bash scripts/check-parity-contract.sh
   terraform init -backend=false
   terraform validate
   terraform test
   bash scripts/validate-release.sh "v$(tr -d '[:space:]' < VERSION)"
   ```

4. Create and push an immutable tag from the validated commit:

   ```bash
   version="$(tr -d '[:space:]' < VERSION)"
   git tag -a "v${version}" -m "Release v${version}"
   git push origin "v${version}"
   ```

The release workflow verifies that the tag matches `VERSION`, belongs to
`main`, references a coherent immutable EC2 release manifest, and passes all
Terraform checks. It then publishes a GitHub release containing the pinned
runner artifacts, security-sensitive changes, and module changelog. Re-run a
failed publication with the workflow's manual trigger and the existing tag;
never move or replace a published tag.
