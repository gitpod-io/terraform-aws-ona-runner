# Restricted runner

This module deploys an Ona AWS runner without an external inbound runner
endpoint. It is a policy wrapper around the repository's root runner module:
it always enables restricted ingress and intentionally omits load-balancer,
certificate, domain, proxy-service, and all other optional root settings from
its interface. It accepts only runner identity and network placement; the root
module owns every default, including the tested runner release version.

Provide an existing VPC and runner subnets with suitable egress. To build a
complete VPC with inspected egress, use the restricted runner with networking
example instead.

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
  vpc_id            = var.vpc_id
  runner_subnet_ids = var.runner_subnet_ids
}
```
