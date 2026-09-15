#!/usr/bin/env bash
set -euo pipefail

terraform fmt -check -recursive
bash scripts/check-parity-contract.sh
terraform init -backend=false
terraform validate
terraform test
bash scripts/test-metrics-audit-sync.sh

for module_dir in modules/*/; do
  if [[ -f "${module_dir}/versions.tf" ]]; then
    terraform -chdir="$module_dir" init -backend=false
    terraform -chdir="$module_dir" validate
    terraform -chdir="$module_dir" test
  fi
done

for example_dir in examples/*/; do
  if [[ -f "${example_dir}/main.tf" ]]; then
    terraform -chdir="$example_dir" init -backend=false
    terraform -chdir="$example_dir" validate
  fi
done

bash scripts/test-restricted-runner-settings.sh
bash scripts/test-firewall-config-errors.sh
bash scripts/test-firewall-migration.sh

git diff --exit-code
