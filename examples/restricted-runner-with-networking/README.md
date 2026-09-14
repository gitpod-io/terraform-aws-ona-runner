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
addresses inside the VPC. Deployments in `us-east-1` use the first runner
subnet for this endpoint to avoid cross-account Availability Zone name mapping;
other regions use every runner subnet.

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

The firewall is enabled by default. Without `firewall_policy_arn`, it permits
the baseline in [`firewall.yaml`](firewall.yaml) plus any
`firewall_allowed_domains`. Other established traffic through the firewall is
dropped and logged. Filtering uses TLS Server Name Indication (SNI).

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

Add deployment-specific hosts in your `.tfvars` file:

```hcl
firewall_allowed_domains = [
  "your-team.atlassian.net",
  "packages.example.com",
]
```

**An empty additional list retains the baseline.** Upgrading from the earlier
empty-allowlist policy therefore enables these baseline services. Review the
plan before upgrading. Supply your own firewall policy if you must remove a
baseline service; disabling the firewall does not restrict access.

Jira site URLs and self-hosted Jira use deployment-specific hosts. Add your
exact hostname if needed, rather than allowing all of `.atlassian.net`.
Azure OpenAI, custom OpenAI-compatible gateways, GitHub Enterprise, and other
registries also need explicit additions. Allowing MCR does not allow package
repositories or devcontainer feature downloads. Test an uncached image pull
and your full environment setup.

An exact name matches that host. A leading dot matches the domain and its
subdomains; do not use `*`, URLs, paths, or ports. Domains are lowercased and
deduplicated. The baseline and additions can contain at most 999 distinct
entries combined.

The policy is not a pull-only, image-repository, account, or API-path allowlist.
It applies to both runner and environment traffic for their entire lifetime.
It does not decrypt TLS, restrict destination ports to 443, or verify that a
destination IP belongs to the claimed SNI. TCP connection establishment is
permitted so the firewall can inspect SNI; unmatched established traffic is
dropped. Use a custom policy or an enforcing proxy if you need stronger
controls. See [AWS domain-list inspection](https://docs.aws.amazon.com/network-firewall/latest/developerguide/stateful-rule-groups-domain-names.html).

Do not add AWS API domains or `app.gitpod.io` to this list. Their interface and
gateway endpoint routes are VPC-local and take precedence over the default
route through Network Firewall. Add only public services required by your
workloads, such as source-control, package-registry, or artifact hosts.

Provide `firewall_policy_arn` to replace the example-managed policy entirely.
When set, both the baseline and `firewall_allowed_domains` are ignored; the
supplied policy defines the inspected egress behavior.

### Keep additional domains in YAML

If you call this example from another root module, keep its extra destinations
in a deployment-owned `firewall-overrides.yaml`:

```yaml
allowed_domains:
  - your-team.atlassian.net
  - packages.example.com
```

Pass that file to the existing input in your module block:

```hcl
firewall_allowed_domains = toset(
  yamldecode(file("${path.module}/firewall-overrides.yaml")).allowed_domains
)
```

The example merges these entries with its bundled baseline. Do not edit files
under `.terraform/modules`; an update can replace them. YAML expressions belong
in `.tf` configuration, not `.tfvars` files.

Set `enable_firewall = false` to omit Network Firewall and route runner traffic
directly to the selected egress target. This removes egress inspection and is
supported but not recommended.

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
