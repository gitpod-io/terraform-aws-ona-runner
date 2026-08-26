# Management-plane custom-domain client infrastructure

This module deploys the customer-side AWS infrastructure needed to reach the
Ona management plane through a custom domain. It follows the AWS architecture
in the [Ona custom-domain guide](https://ona.com/docs/ona/custom-domain):

```text
Client -> TLS Network Load Balancer -> VPC endpoint -> Ona relay
```

The module creates:

- separate security groups for the Network Load Balancer and VPC endpoint;
- a cross-region-capable interface VPC endpoint for the Ona relay service;
- a TCP target group for the endpoint interfaces;
- an internal or internet-facing Network Load Balancer; and
- a TLS listener using the supplied ACM certificate with HTTP/2 preferred.

The target group deliberately does not add Proxy Protocol v2. Ona's
provider-side load balancer adds the trusted header used to identify the VPC
endpoint; the customer load balancer forwards plain TCP after TLS termination.

The existing `../custom-domain-client-infra` module serves a different purpose:
it creates certificate and DNS resources for an Ona runner domain. It does not
route management-plane custom-domain traffic to the Ona relay.

## Prerequisites

Before applying this module:

1. Register the custom domain and this AWS account ID in Ona.
2. Create or select an ACM certificate in the deployment region that covers
   both the base domain and `vscode.<base-domain>`.
3. Select at least two subnets in different Availability Zones.
4. Decide whether users reach the domain through private connectivity or the
   public internet, and provide only the required source CIDRs or security
   groups.

## Usage

```hcl
module "management_plane_custom_domain" {
  source = "gitpod-io/ona-runner/aws//modules/management-plane-custom-domain-client-infra"
  version = "~> 0.2"

  vpc_id     = "vpc-00000000000000000"
  subnet_ids = [
    "subnet-00000000000000001",
    "subnet-00000000000000002",
  ]

  domain_name     = "ona.example.com"
  certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/example"

  allowed_ipv4_cidr_blocks = ["10.0.0.0/8"]
}
```

The default load balancer is internal. Set
`load_balancer_scheme = "internet-facing"` only when the domain should be
publicly reachable, and set `allowed_ipv4_cidr_blocks` accordingly.

## Configure DNS

Create records for both output domain names. They must point to the same
Network Load Balancer:

- `domain_name`, for example `ona.example.com`;
- `vscode_domain_name`, for example `vscode.ona.example.com`.

For Route53, create alias records using `load_balancer_dns_name` and
`load_balancer_zone_id`. Other DNS providers can use CNAME records where the
provider supports them.

When the load balancer is internal, create these records in private DNS that is
reachable from user networks and runner VPCs. A runner created from the custom
domain must resolve the base domain through this load balancer rather than
directly to the VPC endpoint.

After DNS is configured, complete the SSO and runner steps in the
[custom-domain guide](https://ona.com/docs/ona/custom-domain).
