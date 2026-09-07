#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command="$(terraform console -no-color <<<'jsonencode(local.metrics_audit_sync_container.command[0])' | jq -er 'fromjson')"
/bin/sh -n <<<"$command"

test_dir="$(mktemp -d -t ona-metrics-test.XXXXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
mkdir "$test_dir/audit" "$test_dir/bin"
ln -s "$repo_root/tests/fixtures/metrics-audit-aws.sh" "$test_dir/bin/aws"

# Run the rendered container command once against temporary files and a fake AWS CLI.
command="${command//while true; do/for iteration in once; do}"
command="${command//sleep 60/:}"
command="${command//\/audit\//${test_dir}\/audit\/}"

run_once() {
  AWS_TEST_STATUS="$1" AWS_TEST_LOG="$test_dir/uploads" \
    AUDIT_BUCKET="audit-test" RUNNER_ID="runner-test" \
    PATH="$test_dir/bin:$PATH" /bin/sh -c "$command"
}

touch "$test_dir/audit/metrics.json"
run_once 0
test ! -e "$test_dir/uploads"

rotated_file="$test_dir/audit/metrics-rotated file.json"
touch "$rotated_file"
run_once 1
test -f "$rotated_file"
mapfile -t upload_args < "$test_dir/uploads"
test "${#upload_args[@]}" -eq 5
test "${upload_args[0]}" = "s3"
test "${upload_args[1]}" = "cp"
test "${upload_args[2]}" = "$rotated_file"
[[ "${upload_args[3]}" =~ ^s3://audit-test/metrics/runner/runner-test/[0-9]{4}/[0-9]{2}/[0-9]{2}/metrics-rotated\ file.json$ ]]
test "${upload_args[4]}" = "--quiet"

run_once 0
test ! -e "$rotated_file"
test -f "$test_dir/audit/metrics.json"
test "$(wc -l < "$test_dir/uploads")" -eq 10

run_once 0
test "$(wc -l < "$test_dir/uploads")" -eq 10
echo "Metrics audit sync: upload arguments, retries, cleanup, and empty rotations passed."
