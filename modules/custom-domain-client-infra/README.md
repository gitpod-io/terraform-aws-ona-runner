# Custom Domain Client Infrastructure

This module creates the AWS-side DNS and certificate resources commonly needed
for an Ona AWS Runner custom domain.

It creates:

- An ACM certificate for `domain_name` and `*.domain_name`
- Route53 DNS validation records
- Optional Route53 alias records for `domain_name` and `*.domain_name` pointing
  at the runner Network Load Balancer

Use this module separately from the runner module when you want Terraform to own
the certificate and DNS records. The root runner module still accepts
`certificate_arn` directly so customers can bring an existing ACM certificate.

## Inputs and outputs

Set `domain_name` and `hosted_zone_id` for every helper deployment. To create
alias records, set both `load_balancer_dns_name` and
`load_balancer_zone_id`; leave both empty when the helper should create only a
validated certificate. The helper returns `certificate_arn` for the root
runner module, as well as the validation and alias record FQDNs for DNS
verification.

## Usage

```hcl
module "runner_domain" {
  source = "./modules/custom-domain-client-infra"

  domain_name    = "runner.example.com"
  hosted_zone_id = "Z00000000000000000000"
}

module "runner" {
  source = "../.."

  runner_id       = var.runner_id
  runner_token    = var.runner_token
  runner_domain   = module.runner_domain.domain_name
  certificate_arn = module.runner_domain.certificate_arn

  vpc_id                   = var.vpc_id
  runner_subnet_ids        = var.runner_subnet_ids
  load_balancer_subnet_ids = var.load_balancer_subnet_ids
}
```

After the runner is created, pass `module.runner.load_balancer_dns_name` and
`module.runner.load_balancer_zone_id` to this module, or create equivalent alias
records in your DNS system.

## Upgrading

The validation records are keyed by their ACM record name, because ACM returns
one shared CNAME for `domain_name` and `*.domain_name`. If you upgrade from a
module version that keyed them by domain name, move the existing state entry
before applying the upgrade. This prevents Terraform from deleting and
recreating the certificate validation CNAME.

First, use `terraform state show` to obtain the ACM validation record name, then
move its state entry. For example:

```sh
terraform state mv \
  'module.runner_domain.aws_route53_record.validation["runner.example.com"]' \
  'module.runner_domain.aws_route53_record.validation["_abc123.runner.example.com."]'
```

Use the module name, existing state address, and ACM record name from your own
state. Run `terraform plan` afterwards and confirm it does not replace the
validation record.
