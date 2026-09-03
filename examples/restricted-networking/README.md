# Restricted networking

This example creates networking for Ona AWS runner egress. Runner subnets have
no public IP addresses, and the VPC has no load-balancer or other inbound
endpoint subnets. It supports either module-managed NAT Gateways or a
customer-provided Transit Gateway.

Copy `terraform.tfvars.example` to a `.tfvars` file and provide the CIDR,
region, and availability-zone values.

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

The networking module creates a VPC attachment with one attachment subnet per
availability zone. Appliance mode is enabled when the firewall is enabled. The
Transit Gateway must already have a default route to working centralized
egress. Its route table must also propagate or contain a return route for the
runner CGNAT CIDR through the VPC attachment. Shared Transit Gateways can
require acceptance by their owner.

## Firewall policy

The firewall is enabled by default. Without `firewall_policy_arn`, the example
uses the networking module's permissive inspection policy. Provide an existing
Network Firewall policy to enforce customer-specific egress rules.

Set `enable_firewall = false` to omit Network Firewall and route runner traffic
directly to the selected egress target. This removes egress inspection and is
supported but not recommended.

The example does not create workload security groups. The follow-up runner
deployment must deny unsolicited ingress to workloads that use these subnets.
