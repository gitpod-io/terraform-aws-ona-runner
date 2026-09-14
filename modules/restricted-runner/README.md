# Restricted runner

This module deploys an Ona AWS runner without an external inbound runner
endpoint. It is a policy wrapper around the repository's root runner module:
it always enables restricted ingress and intentionally omits load-balancer,
certificate, domain, and proxy-service settings from its interface. It accepts
runner identity, an optional runner name, network placement, outbound proxy
settings, and a custom CA trust bundle. The root module owns every other
default, including the tested runner release version.

Provide an existing VPC and runner subnets with suitable egress. To build a
complete VPC with inspected egress, use the restricted runner with networking
[example](../../examples/restricted-runner-with-networking/README.md) instead.

`runner_name` controls the AWS resource-name prefix. The runner's display name
in Ona is configured when the runner record is created.

The module creates no resources independently. All runner resources are owned
by the child root module, so validation errors and resource behavior remain
consistent with the standard runner implementation.

## Usage

```hcl
module "runner" {
  source  = "gitpod-io/ona-runner/aws//modules/restricted-runner"
  version = "~> 0.2"

  runner_id         = var.runner_id
  runner_token      = var.runner_token
  runner_name       = "production-runner"
  vpc_id            = var.vpc_id
  runner_subnet_ids = var.runner_subnet_ids
}
```

## Network requirements

**Restricted ingress does not restrict egress.** This wrapper creates no VPC,
endpoints, routes, or Network Firewall. Its workload security groups permit
outbound IPv4 traffic. Your network must enforce the approved destination list.

- Use private subnets in two or three Availability Zones, with VPC DNS enabled.
- Provide private endpoints or approved egress for AWS services and Ona. See
  [AWS networking requirements](https://ona.com/docs/ona/runners/aws/networking).
- Allow TCP 443 to interface endpoints from the runner subnet CIDRs, covering
  the Fargate tasks and environment VMs. Retain the module's internal runner
  and environment security-group rules.
- Route public egress through your firewall or enforcing proxy, with a symmetric
  return path. No inbound user endpoint, runner domain, or load balancer is needed.

The [networking example's firewall guide](../../examples/restricted-runner-with-networking/README.md#firewall-policy)
lists its baseline for GitHub, Linear, Jira Cloud, OpenAI, and MCR, including
base-image layer endpoints and the three policy configuration options. Use that
as a reference for your own policy; this wrapper does not install the baseline
or accept the networking example's firewall inputs.

## Outbound proxy and custom CA

Set these optional inputs on the module block:

```hcl
proxy_config = {
  http_proxy  = "http://proxy.example.com:3128"
  https_proxy = "http://proxy.example.com:3128"
}
custom_ca_trust_bundle = "s3://gitpod-example/shared/ca-bundle.pem"
```

`proxy_config` accepts `http_proxy`, `https_proxy`, `all_proxy`, and `no_proxy`.
Omitted fields retain the root module defaults: the three proxy URLs are empty
and `no_proxy` is
`localhost,127.0.0.1,.internal,.amazonaws.com,169.254.0.0/16,app.gitpod.io`.
If you override `no_proxy`, preserve the private AWS, metadata, internal runner,
and management-plane destinations and add any other private hosts that must
bypass the proxy.

`custom_ca_trust_bundle` accepts PEM content or a runner-supported bundle URL,
such as the S3 URL above or an HTTPS URL. It defaults to an empty string. The
settings feed the existing runner and telemetry task configuration and CA
initialization. They do not enable the inbound proxy service or change network
rules. The proxy and CA source must be reachable through your existing network
policy. CA initialization downloads the bundle before the runner starts and
does not inherit `proxy_config`; use a directly reachable bundle source.

For S3, the task roles permit CA reads from `gitpod-*` buckets;
bucket policies and any KMS permissions must also permit access. For SSM,
resolve the value with Terraform and pass the resulting PEM content;
CloudFormation `{{resolve:ssm:...}}` references are not expanded by Terraform.
Custom trust is not automatically installed in devcontainer images or image
builds. See the [AWS setup guide](https://ona.com/docs/ona/runners/aws/setup#custom-ca-certificate)
for runtime limitations.
