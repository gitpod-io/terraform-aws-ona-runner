#!/usr/bin/env bash
set -euo pipefail

# Terraform assertions cannot inspect child-module resources. Check the rendered
# task definitions from provider-mocked plans without adding diagnostic outputs.
check_settings() {
  local module_dir="$1"
  local test_file="$2"

  echo "Checking restricted CA/proxy passthrough: ${module_dir}"
  terraform -chdir="$module_dir" test -filter="$test_file" -json -verbose |
    jq -es '
      def environment:
        (.environment // [] | map({key: .name, value: .value}) | from_entries);
      def proxy_environment:
        environment | with_entries(select(.key | test("^(http_proxy|https_proxy|all_proxy|no_proxy)$")));

      "localhost,127.0.0.1,.internal,.amazonaws.com,169.254.0.0/16,app.gitpod.io" as $bypass |
      [.[] | select(.type == "test_plan") |
        select(.["@testrun"] | startswith("ca_proxy_")) |
        {run: .["@testrun"], resources: .test_plan.resource_changes}
      ] as $runs |
      ($runs | map(.run) | sort) == ["ca_proxy_custom", "ca_proxy_defaults", "ca_proxy_partial"] and
      all($runs[];
        (if .run == "ca_proxy_custom" then {
          ca: "s3://gitpod-example/shared/ca-bundle.pem",
          proxy: {
            http_proxy: "http://proxy.example.com:3128",
            https_proxy: "http://proxy.example.com:3129",
            all_proxy: "socks5://proxy.example.com:1080",
            no_proxy: ($bypass + ",.corp.example")
          }
        } elif .run == "ca_proxy_partial" then {
          ca: "",
          proxy: {https_proxy: "http://proxy.example.com:3128", no_proxy: $bypass}
        } else {
          ca: "",
          proxy: {no_proxy: $bypass}
        } end) as $expected |
        [.resources[] | select(.type == "aws_ecs_task_definition")] as $tasks |
        [$tasks[].change.after.container_definitions | fromjson | .[]] as $containers |
        [$containers[] | select(.name == "init-container")] as $init |
        [$containers[] | select(.name != "init-container")] as $runtime |

        ($tasks | map(.name) | sort) == ["adot", "runner"] and
        ($init | length) == 2 and
        all($init[]; (environment.GITPOD_CUSTOM_CA_BUNDLE == $expected.ca)) and
        ($runtime | map(.name) | sort) == ["aws-otel-collector", "ec2-runner", "metrics-audit-sync"] and
        all($runtime[]; proxy_environment == $expected.proxy) and
        all($runtime[] | select(.name == "ec2-runner"); environment.GITPOD_CUSTOM_CA_BUNDLE == $expected.ca) and
        ([.resources[] | select(.type == "aws_lb" or (.type == "aws_ecs_service" and .name == "proxy"))] | length) == 0
      )
    '
}

check_api_endpoint() {
  local module_dir="$1"
  local test_file="$2"

  echo "Checking restricted API endpoint passthrough: ${module_dir}"
  terraform -chdir="$module_dir" test -filter="$test_file" -json -verbose |
    jq -es '
      [.[] | select(.type == "test_plan") |
        select(.["@testrun"] | startswith("api_endpoint_")) |
        {
          run: .["@testrun"],
          config: ([.test_plan.resource_changes[] |
            select(.type == "aws_ssm_parameter" and .name == "runner_config") |
            .change.after.value | fromjson] | .[0])
        }
      ] as $runs |
      ($runs | map(.run) | sort) == ["api_endpoint_custom", "api_endpoint_default"] and
      all($runs[];
        .config.apiEndpoint == (if .run == "api_endpoint_custom" then
          "https://runner-api.example.com/api"
        else
          "https://app.gitpod.io/api"
        end)
      )
    '
}

check_settings modules/restricted-runner tests/restricted_runner.tftest.hcl
check_settings examples/restricted-runner-with-networking tests/networking.tftest.hcl
check_api_endpoint modules/restricted-runner tests/restricted_runner.tftest.hcl
check_api_endpoint examples/restricted-runner-with-networking tests/networking.tftest.hcl
