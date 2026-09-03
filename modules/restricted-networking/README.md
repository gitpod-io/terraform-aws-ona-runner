# Restricted networking

This module creates IPv4 networking for Ona AWS runner egress. It creates no
load-balancer or other inbound endpoint subnets. It supports two egress modes:

- `nat_gateway` creates an internet gateway and one NAT Gateway per availability
  zone.
- `transit_gateway` creates an appliance-mode VPC attachment to a customer
  Transit Gateway. The customer remains responsible for the Transit Gateway
  route table, downstream egress, and return routing to the runner CGNAT CIDR.

The primary VPC CIDR supplies firewall and NAT Gateway or Transit Gateway
attachment subnets. A secondary `/16` from `100.64.0.0/10` supplies runner
subnets. The module reserves the second half of that CGNAT block without
creating subnets in it.

For two availability zones, the active CGNAT `/17` becomes two `/18` runner
subnets. For three availability zones, it becomes three `/19` runner subnets
and one spare `/19`.

## Routing

With the firewall enabled, NAT Gateway mode uses this path in each availability
zone:

```text
runner subnet -> Network Firewall endpoint -> NAT Gateway -> internet gateway
```

Transit Gateway mode uses:

```text
runner subnet -> Network Firewall endpoint -> Transit Gateway -> customer egress
```

The egress or attachment subnet route table sends the active runner CIDR back
through the same-zone firewall endpoint. Transit Gateway appliance mode keeps
both directions of a flow in the same availability zone.

Set `enable_firewall = false` to route runner traffic directly to the same-zone
NAT Gateway or to the Transit Gateway. In that mode the module disables Transit
Gateway appliance mode and does not create firewall subnets, a firewall policy,
a firewall, or firewall log groups. Disabling the firewall removes egress
inspection and is not recommended.

## Firewall policy

When the firewall is enabled, the module creates a permissive strict-order
firewall policy by default. It forwards traffic to the stateful engine and
alerts on established flows. Supply `firewall_policy_arn` to enforce a
customer-managed allowlist or threat policy. Network Firewall flow and alert
logs are enabled whenever the firewall is enabled.

## Logging

The module sends these logs to CloudWatch Logs:

- Network Firewall flow logs, when the firewall is enabled
- Network Firewall alert logs, when the firewall is enabled
- VPC Flow Logs for accepted and rejected traffic
- Route 53 Resolver query logs associated with the VPC

Resolver query logging records unique queries rather than responses served from
the Resolver cache. Full flow and query logging can generate substantial data;
set an appropriate retention period.

If `log_kms_key_arn` is set, the key policy must permit the AWS logging services
used by the module.

This module does not create workload security groups. The runner deployment
that consumes these subnets remains responsible for denying unsolicited
ingress.
