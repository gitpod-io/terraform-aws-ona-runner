# Terraform & AWS Development Environment

This dev container is configured for developing and deploying the Ona AWS Runner Terraform module.

## Included Tools

- Terraform
- AWS CLI v2
- Git LFS
- pre-commit
- terraform-docs
- shellcheck
- jq and common archive/download utilities

## Verification

Run this after the container builds:

```bash
terraform --version
aws --version
terraform-docs --version
pre-commit --version
```
