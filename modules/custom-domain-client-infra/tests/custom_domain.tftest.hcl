mock_provider "aws" {
  override_during = plan

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        {
          resource_record_name  = "_abc123.runner.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_validation.acm-validations.aws."
        },
      ]
    }
  }
}

variables {
  domain_name    = "runner.example.com"
  hosted_zone_id = "Z00000000000000000000"
}

run "certificate_only_configuration_does_not_create_alias_records" {
  command = plan

  variables {
    create_alias_records = false
  }

  assert {
    condition     = output.runner_record_fqdn == "" && output.wildcard_record_fqdn == ""
    error_message = "certificate-only configuration must not create runner alias records."
  }
}

run "alias_records_use_both_load_balancer_values" {
  command = plan

  variables {
    load_balancer_dns_name = "internal-runner-123.us-east-1.elb.amazonaws.com"
    load_balancer_zone_id  = "Z26RNL4JYFTOTI"
  }

  assert {
    condition     = aws_route53_record.runner[0].alias[0].name == "internal-runner-123.us-east-1.elb.amazonaws.com"
    error_message = "runner alias record must target the provided Network Load Balancer."
  }
}

run "alias_records_reject_incomplete_load_balancer_inputs" {
  command = plan

  variables {
    load_balancer_dns_name = "internal-runner-123.us-east-1.elb.amazonaws.com"
  }

  expect_failures = [aws_acm_certificate.runner]
}
