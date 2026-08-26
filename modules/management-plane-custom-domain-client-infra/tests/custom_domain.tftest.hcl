mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_network_interface" {
    defaults = {
      private_ip = "10.0.1.10"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-west-2"
    }
  }
}

variables {
  vpc_id                   = "vpc-00000000000000000"
  subnet_ids               = ["subnet-00000000000000001", "subnet-00000000000000002"]
  domain_name              = "ona.example.com"
  certificate_arn          = "arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  allowed_ipv4_cidr_blocks = ["10.0.0.0/8"]
}

run "internal_custom_domain_matches_the_aws_relay_contract" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.relay.service_name == "com.amazonaws.vpce.us-east-1.vpce-svc-00fa18d41fdd25cad" && aws_vpc_endpoint.relay.service_region == "us-east-1" && !aws_vpc_endpoint.relay.private_dns_enabled
    error_message = "the VPC endpoint must connect to the production Ona relay service without private DNS."
  }

  assert {
    condition     = aws_lb.this.internal && aws_lb.this.enable_cross_zone_load_balancing
    error_message = "the default load balancer must be internal and span the configured Availability Zones."
  }

  assert {
    condition     = aws_lb_target_group.relay.protocol == "TCP" && aws_lb_target_group.relay.port == 443 && !aws_lb_target_group.relay.preserve_client_ip && !aws_lb_target_group.relay.proxy_protocol_v2
    error_message = "the load balancer must forward plain TCP 443 after TLS termination because the Ona service adds the trusted Proxy Protocol header."
  }

  assert {
    condition     = aws_lb_listener.https.protocol == "TLS" && aws_lb_listener.https.alpn_policy == "HTTP2Preferred" && aws_lb_listener.https.certificate_arn == var.certificate_arn
    error_message = "the load balancer must terminate TLS with HTTP/2 preferred and the configured certificate."
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.relay) == 2
    error_message = "each VPC endpoint network interface must be registered as a load-balancer target."
  }

  assert {
    condition     = output.aws_account_id == "123456789012" && output.domain_name == "ona.example.com" && output.vscode_domain_name == "vscode.ona.example.com"
    error_message = "the module must expose the custom-domain values required by Ona and DNS configuration."
  }
}

run "internet_facing_custom_domain_is_explicit" {
  command = plan

  variables {
    load_balancer_scheme     = "internet-facing"
    allowed_ipv4_cidr_blocks = ["0.0.0.0/0"]
  }

  assert {
    condition     = !aws_lb.this.internal && aws_vpc_security_group_ingress_rule.load_balancer_ipv4["0.0.0.0/0"].from_port == 443
    error_message = "internet-facing mode must expose only the explicitly allowed HTTPS source ranges."
  }
}

run "security_group_ingress_can_replace_cidr_ingress" {
  command = plan

  variables {
    allowed_ipv4_cidr_blocks   = []
    allowed_security_group_ids = ["sg-00000000000000001"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.load_balancer_ipv4) == 0 && aws_vpc_security_group_ingress_rule.load_balancer_security_group["sg-00000000000000001"].to_port == 443
    error_message = "security-group ingress must allow HTTPS without requiring a CIDR rule."
  }
}

run "custom_domain_requires_an_ingress_source" {
  command = plan

  variables {
    allowed_ipv4_cidr_blocks = []
  }

  expect_failures = [aws_security_group.load_balancer]
}

run "custom_domain_requires_two_subnets" {
  command = plan

  variables {
    subnet_ids = ["subnet-00000000000000001"]
  }

  expect_failures = [var.subnet_ids]
}

run "custom_domain_rejects_a_cross_region_certificate" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [aws_lb_listener.https]
}
