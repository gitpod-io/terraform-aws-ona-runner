# Runner with existing networking

This example deploys a runner into an existing VPC. Copy
`terraform.tfvars.example` for the standard topology with a runner proxy and
Network Load Balancer.

Copy `restricted.terraform.tfvars.example` to deploy without an ingress proxy,
load balancer, public runner DNS, ACM certificate, or load-balancer subnets.
The VPC must have DNS support and DNS hostnames enabled so environments can
resolve the private runner service used for authenticated LLM requests.
