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

## VPC endpoints

The example creates the interface and gateway endpoints listed in the public
[AWS runner networking documentation](https://ona.com/docs/ona/runners/aws/networking#vpc-endpoints-reference).
Regional interface endpoints use private DNS and span every runner subnet. S3
and DynamoDB use gateway endpoints associated with every runner route table.

The example also creates the documented cross-region Ona interface endpoint
with private DNS enabled, so `app.gitpod.io` resolves to the endpoint's private
addresses inside the VPC. Deployments in `us-east-1` use the first runner
subnet for this endpoint to avoid cross-account Availability Zone name mapping;
other regions use every runner subnet.

Private DNS sends AWS API and `app.gitpod.io` traffic over VPC-local routes,
and the S3 and DynamoDB gateway routes take precedence over the default route.
These endpoint paths therefore do not cross Network Firewall.

All interface endpoints share one security group. Its only ingress rules allow
TCP port 443 from the runner ECS security group and the environment EC2
security group created by the restricted runner module. Because security groups
are stateful, the endpoint security group does not need a separate egress rule
for response traffic.

Interface endpoints incur hourly and data-processing charges in each selected
Availability Zone. S3 and DynamoDB gateway endpoints do not have hourly
charges.

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

The firewall is enabled by default. Without `firewall_policy_arn`, the example
creates a permissive strict-order policy that forwards traffic to the stateful
engine and alerts on established flows. Provide an existing Network Firewall
policy to enforce customer-specific egress rules.

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
