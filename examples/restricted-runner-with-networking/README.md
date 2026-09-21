# Restricted runner with networking

This example creates a complete AWS network for Ona runner egress and passes
its VPC and subnet resources to the restricted runner module. Runner subnets
have no public IP addresses, and the VPC has no load-balancer or other inbound
endpoint subnets. It supports either example-managed NAT Gateways or a
customer-provided Transit Gateway.

Copy `terraform.tfvars.example` to a `.tfvars` file and provide the runner
credentials, CIDR, region, and availability-zone values. `runner_name` is
optional and defaults to `ona-runner`. The restricted runner module does not
expose a restriction toggle and does not require a runner domain, ACM
certificate, or load-balancer subnets.

`runner_name` controls the AWS resource-name prefix. The runner's display name
in Ona is configured when the runner record is created.

`network_name` is optional. When omitted, the example derives the same unique
prefix shape from `runner_name` and `runner_id`; set it explicitly only when a
specific existing network-resource prefix must be preserved.

The network resources intentionally live directly in this example. Inspect and
adapt them for your organization's egress policy instead of treating this
topology as a separately supported networking module.

## Deploy

This example requires AWS provider `~> 6.60.0` for dynamic firewall membership.
When upgrading, update any provider 5.x constraint in your root configuration,
run `terraform init -upgrade`, and review the plan before applying. See the
[AWS provider 6 upgrade guide](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-6-upgrade).

From this directory, copy `terraform.tfvars.example` to `terraform.tfvars` and
fill in your runner registration and network values. Review the
[baseline outbound access](#firewall-policy) before deploying:

```shell
terraform init
terraform plan -out=runner.tfplan
terraform apply runner.tfplan
```

Keep credentials, state, and saved plans out of version control. Use the
[restricted runner module](../../modules/restricted-runner/README.md) instead
if your team already owns the VPC, firewall, and endpoints.

## VPC endpoints

The example creates the interface and gateway endpoints listed in the public
[AWS runner networking documentation](https://ona.com/docs/ona/runners/aws/networking#vpc-endpoints-reference).
Regional interface endpoints use private DNS and span every runner subnet. S3
and DynamoDB use gateway endpoints associated with every runner route table.

IAM is the exception to regional service naming: its service is
`com.amazonaws.iam` in `us-east-1`. Outside `us-east-1`, the example creates a
local interface endpoint with `service_region = "us-east-1"` using
[cross-region AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-cross-region-privatelink-support.html).
Private DNS keeps IAM API traffic on the private endpoint path without a
public firewall allowlist entry. The identity deploying this example needs
`vpce:AllowMultiRegion`, and its organization's service control policies must
not deny that permission. In `us-east-1`, the IAM endpoint stays in-region.

The example also creates the documented cross-region Ona interface endpoint
with private DNS enabled, so `app.gitpod.io` resolves to the endpoint's private
addresses inside the VPC. Deployments in `us-east-1` query the endpoint service
and use the first configured runner subnet that it supports; Terraform stops
with an explicit error when none of the configured zones are compatible. Other
regions use every runner subnet because cross-region PrivateLink does not
require matching Availability Zones.

`api_endpoint` defaults to `https://app.gitpod.io/api` and is forwarded to the
runner. For a custom management plane domain, set
`api_endpoint = "https://ona.example.com/api"` in `terraform.tfvars`. This does
not change the `app.gitpod.io` PrivateLink endpoint, DNS, firewall rules, or
proxy bypass settings. Configure those separately so the custom hostname is
reachable through your approved network path.

Private DNS sends AWS API and `app.gitpod.io` traffic over VPC-local routes,
and the S3 and DynamoDB gateway routes take precedence over the default route.
These endpoint paths therefore do not cross Network Firewall.

All interface endpoints share one security group. Its only ingress rules allow
TCP port 443 from the runner subnet CIDRs, covering both runner ECS tasks and
environment EC2 instances in those dedicated subnets. Because security groups
are stateful, the endpoint security group does not need a separate egress rule
for response traffic.

Interface endpoints incur hourly and data-processing charges in each selected
Availability Zone. S3 and DynamoDB gateway endpoints do not have hourly
charges.

## Outbound proxy and custom CA

The example forwards `proxy_config` and `custom_ca_trust_bundle` through the
restricted runner module. Add them to your `.tfvars` file when needed:

```hcl
proxy_config = {
  http_proxy  = "http://proxy.example.com:3128"
  https_proxy = "http://proxy.example.com:3128"
}
custom_ca_trust_bundle = "s3://gitpod-example/shared/ca-bundle.pem"
```

See [the restricted module's proxy and CA settings](../../modules/restricted-runner/README.md#outbound-proxy-and-custom-ca)
for supported fields, bypass defaults, and CA-source requirements. Preserve
the default `no_proxy` entries so AWS and management-plane traffic continues to
use the VPC endpoints.

These inputs do not add firewall rules or deploy a proxy. The proxy and CA source
must already be reachable. A proxy connection routed through Network Firewall
is still subject to its default-deny policy; the domain allowlist only permits
TLS-SNI traffic, not arbitrary plain-HTTP CONNECT traffic to a proxy. If you use
a customer firewall policy, permit only the required proxy path. A proxy on a
VPC-local route bypasses Network Firewall. In either case, the proxy's own
destination policy must enforce the intended egress restrictions.

## Network layout

The primary VPC CIDR supplies firewall and NAT Gateway or Transit Gateway
attachment subnets. A secondary `/16` from `100.64.0.0/10` supplies runner
subnets. The example uses its first `/17` and reserves the second `/17` without
creating subnets in it.

With two availability zones, the active `/17` becomes two `/18` runner
subnets. With three availability zones, it becomes three `/19` runner subnets
and one spare `/19`.

## NAT Gateway mode

The default mode creates one NAT Gateway and Elastic IP per availability zone,
plus an internet gateway. It is self-contained:

```hcl
egress = {
  mode = "nat_gateway"
}
```

## Transit Gateway mode

Provide an existing Transit Gateway:

```hcl
egress = {
  mode               = "transit_gateway"
  transit_gateway_id = "tgw-0123456789abcdef0"
}
```

The example creates a VPC attachment with one attachment subnet per
availability zone. Appliance mode is enabled when the firewall is enabled. The
Transit Gateway must already have a default route to working centralized
egress. Its route table must propagate or contain a return route for each
runner subnet CIDR through the VPC attachment. Shared Transit Gateways can
require acceptance by their owner.

## Routing

With the firewall enabled, each availability zone has a symmetric path:

```text
NAT Gateway:     runner subnet -> firewall endpoint -> NAT Gateway -> internet gateway
Transit Gateway: runner subnet -> firewall endpoint -> Transit Gateway -> customer egress
```

Each NAT Gateway or Transit Gateway attachment subnet route table sends every
runner subnet CIDR back through its same-zone firewall endpoint. Transit
Gateway appliance mode keeps both directions of a flow in the same
availability zone.

## Firewall policy

The firewall is enabled by default. Three stateful rule groups combine dynamic
source membership with TLS Server Name Indication (SNI):

- **Runner:** all Fargate tasks in the dedicated ECS cluster, including telemetry.
- **Environments:** assigned EC2 instances for this runner with the `default`,
  `workflow`, or `base-snapshot-build` environment role.
- **Prebuilds:** assigned EC2 instances for this runner with the `prebuild` role.

AWS maintains membership as tasks and instances change; no per-IP Terraform
updates are needed. Unmatched established traffic is dropped and logged.
The bundled [`firewall.yaml`](firewall.yaml) has explicit lists for all three
roles. They start with the same baseline for upgrade compatibility and can be
edited independently in a custom YAML file.
Choose one of the three configuration methods below. The generated policy also
contains the explicit `containers.dev` rejection described below.

| Service | Baseline domains | Purpose |
| --- | --- | --- |
| Linear | `api.linear.app` | Read and publish issues. |
| GitHub | `github.com`, `api.github.com`, `codeload.github.com`, `.githubusercontent.com` | HTTPS Git access, repository APIs, source archives, raw files, and release assets. |
| Jira Cloud | `api.atlassian.com` | Issue access through the OAuth API gateway. |
| OpenAI | `api.openai.com` | Direct model access with your own API key. |
| Microsoft Container Registry | `mcr.microsoft.com`, `.data.mcr.microsoft.com` | Base-image manifests and image-layer downloads. |

The YAML comments explain each entry. Endpoint references:
[Linear](https://linear.app/developers/graphql),
[GitHub](https://docs.github.com/en/code-security/reference/supply-chain-security/automatic-dependency-submission#required-urls-for-all-ecosystems),
[Jira Cloud](https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/#authentication),
[OpenAI](https://platform.openai.com/docs/api-reference/responses), and
[MCR](https://github.com/microsoft/containerregistry/blob/main/docs/client-firewall-rules.md).

### 1. Use an existing firewall policy

Set the ARN of your AWS Network Firewall **policy**, not a rule group, in your
`.tfvars` file:

```hcl
firewall_policy_arn = "arn:aws:network-firewall:eu-central-1:123456789012:firewall-policy/customer-policy"
```

Your policy replaces the generated policy. The baseline and
`firewall_allowed_domains` are ignored; leave `firewall_config_path` unset.

### 2. Add domains to the baseline

Keep the [bundled allowlist](firewall.yaml) and add deployment-specific hosts
for the runner, normal environments, and prebuilds in your `.tfvars` file:

```hcl
firewall_allowed_domains = [
  "your-team.atlassian.net",
  "packages.example.com",
]
```

**An empty additional list retains the baseline.** Upgrading from the earlier
empty-allowlist policy therefore enables these baseline services. Review the
plan before upgrading. To remove baseline entries, use your own YAML file or
policy ARN instead.

### 3. Replace the allowlist with your own YAML file

Copy [`firewall.yaml`](firewall.yaml) into your deployment directory and edit
its `runner_allowed_domains`, `environment_allowed_domains`, and
`prebuild_allowed_domains` lists. Your file supplies the **complete
allowlists** without merging the baseline or additional domains.

When running this example directly, make a separate copy:

```shell
cp firewall.yaml firewall-custom.yaml
```

Edit `firewall-custom.yaml`, then set its path in `terraform.tfvars`:

```hcl
firewall_config_path = "./firewall-custom.yaml"
```

When calling the example from your own root module, put your copy at
`firewall.yaml` next to your `main.tf` and add this argument **inside the module
block**:

```hcl
firewall_config_path = "${path.module}/firewall.yaml"
```

Leave `firewall_policy_arn` unset and `firewall_allowed_domains` empty. To deny
all firewall-routed traffic, set `allowed_domains: []`, or set all three role
lists to `[]`. Private endpoint routes are unaffected. YAML configures the TLS
hostname allowlist; for other rule types, use a policy ARN.

#### Separate runner, environment, and prebuild access

Edit the three lists independently. For example, this replacement allows model
access from the runner, base-image downloads from normal environments, and a
narrower set of package downloads from prebuilds:

```yaml
runner_allowed_domains:
  - api.openai.com
environment_allowed_domains:
  - mcr.microsoft.com
  - .data.mcr.microsoft.com
prebuild_allowed_domains:
  - mcr.microsoft.com
```

Set `firewall_config_path` as above. These lists do not inherit the baseline or
each other; add any repository, integration, and package hosts your workflow
needs to the role that calls them. `[]` gives that role no allow exceptions.
For one shared list, replace all three keys with `allowed_domains`; do not
combine the shared and separate forms.

The file must exist wherever Terraform runs before planning. A missing file,
invalid YAML, unknown key, or invalid hostname fails the plan; it never falls
back to the baseline. Do not edit `.terraform/modules`, which Terraform can
replace during an update.

### Control manifest requests

When `containers.dev` is not allowlisted, the generated policy rejects TLS
connections to that exact hostname on TCP port 443 from the runner subnets.
The reject rule runs before the domain allowlist's generated drop rule and
sends a TCP reset instead of silently dropping the request. This lets the
Dev Containers CLI use its existing fallback without waiting for a network
timeout. See the [upstream issue](https://github.com/microsoft/vscode-remote-release/issues/8808).

The rule covers both runner tasks and environment VMs, including test sessions,
in this dedicated network. It matches the hostname, not just the manifest URL
path. Other destinations, subdomains, ports, and private endpoint routes retain
their existing behavior. An outbound proxy that bypasses Network Firewall
requires its own policy.

Explicitly allowing `containers.dev` or `.containers.dev` for either role omits
the subnet-scoped reject rule. A role that does not allow the hostname still
gets the policy's normal default denial, without the prompt reset. A custom
`firewall_policy_arn` remains entirely caller-managed. An empty YAML allowlist
keeps its deny-all policy and does not add this rule or permit TCP establishment.

Blocked requests do not refresh feature safety data: CLI 0.84.1 uses the cached
manifest if present, or an empty manifest otherwise. This does not disable
feature installation or allow feature downloads.

Existing deployments must apply the updated Terraform configuration. Review
the plan for a new stateful rule group and an in-place policy update; no runner
or VM replacement is required by this change. After the firewall update has
propagated, retry with a new connection and verify a prompt reset and a matching
firewall alert. Restart an already-stuck devcontainer invocation, then check
that a test session starts and previously allowed destinations still work.

### Domain matching and scope

Jira site URLs and self-hosted Jira use deployment-specific hosts. Add your
exact hostname if needed, rather than allowing all of `.atlassian.net`.
Azure OpenAI, custom OpenAI-compatible gateways, GitHub Enterprise, and other
registries also need explicit additions. Allowing MCR does not allow package
repositories or devcontainer feature downloads. Test an uncached image pull
and your full environment setup.

An exact name matches that host. A leading dot matches the domain and its
subdomains; do not use `*`, URLs, paths, or ports. Domains are lowercased and
deduplicated. Each role's allowlist can contain at most 999 distinct entries.

The policy is not a pull-only, image-repository, account, or API-path allowlist.
Each role's list applies for the workload's entire lifetime.
It does not decrypt TLS, restrict destination ports to 443, or verify that a
destination IP belongs to the claimed SNI. TCP connection establishment is
permitted so the firewall can inspect SNI; unmatched established traffic is
dropped. Use a custom policy or an enforcing proxy if you need stronger
controls. See [AWS domain-list inspection](https://docs.aws.amazon.com/network-firewall/latest/developerguide/stateful-rule-groups-domain-names.html).

Do not add AWS API domains or `app.gitpod.io` to this list. Their interface and
gateway endpoint routes are VPC-local and take precedence over the default
route through Network Firewall. Add only public services required by your
workloads, such as source-control, package-registry, or artifact hosts.

Set `enable_firewall = false` to omit Network Firewall and route runner traffic
directly to the selected egress target. This removes egress inspection and is
supported but not recommended.

### Membership and upgrade considerations

Unclaimed warm-pool instances have no environment-ID tag and receive no
environment allowlist exceptions. They become eligible after assignment adds
the tag and AWS updates membership. Private endpoint access is unaffected.

The firewall sees original source IPs before NAT. Membership updates are
asynchronous, not an instantaneous identity check. Test task replacement,
instance stop/start, warm pools, and IP reuse before relying on this separation
for hostile workloads. Private endpoint and VPC-local traffic still uses
security groups and IAM, not this egress policy. Do not route environment
egress through a runner-side proxy that would hide its source IP.

Keep the ECS cluster dedicated and protect ownership tags. Environment IAM
permits only operational self-tagging, not changes to `gitpod.dev/runner-id`,
`gitpod.dev/environment-id`, or `gitpod.dev/environment-role`; do not broaden
it to allow membership or ECS control.
The deploying identity needs Resource Groups and Network Firewall management permissions,
`ecs:DescribeClusters`, and first-use `iam:CreateServiceLinkedRole`.
See [AWS container associations](https://docs.aws.amazon.com/network-firewall/latest/developerguide/container-associations.html)
and [tag-based groups](https://docs.aws.amazon.com/network-firewall/latest/developerguide/resource-group-creating.html).

#### Upgrade an existing firewall

Update the module and run a fresh `terraform plan` before applying. No state
edits or manual AWS policy changes are needed for the original shared-group
deployment. Terraform updates `<network_name>-allowed-domains` in place for
runner traffic and adds `<network_name>-environment-domains` for normal
environments and `<network_name>-prebuild-domains` for prebuilds. The firewall,
policy, subnets, and routes remain in place.

Existing shared YAML and additional-domain inputs retain their destinations for
all three roles; other sources no longer receive those exceptions. An empty
role list keeps its group with a deny-only rule, so removing the last domain
does not delete an attached group. Allow for a brief interruption to public
egress while rules and membership propagate, then verify connectivity.

## Logging

The example sends Network Firewall flow and alert logs to CloudWatch Logs when
the firewall is enabled. It also sends accepted and rejected VPC Flow Logs and
Route 53 Resolver query logs to CloudWatch Logs. Resolver query logging records
unique queries rather than responses served from the Resolver cache.

Full flow and query logging can generate substantial CloudWatch ingestion and
storage costs, so choose an appropriate retention period. If
`log_kms_key_arn` is set, its key policy must permit the AWS logging services
used by this example.

The restricted runner module creates the workload security groups and limits
environment ingress to the supervisor control and private LLM paths required
by the restricted topology.
