#!/usr/bin/env bash
set -euo pipefail

terraform fmt -check -recursive
bash scripts/check-parity-contract.sh
bash scripts/test-aws-provider.sh

git diff --exit-code
