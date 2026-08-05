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

- [Terraform](https://terraform.io/) >= 1.7
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
