mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
}

mock_provider "random" {}

variables {
  runner_id                = "019d6999-807b-7e52-ab6f-c9202f13ecf2"
  runner_token             = "test-token"
  runner_domain            = "runner.example.com"
  certificate_arn          = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  vpc_id                   = "vpc-00000000000000000"
  runner_subnet_ids        = ["subnet-00000000000000000"]
  load_balancer_subnet_ids = ["subnet-00000000000000000"]
}

run "runner_id_hash_distinguishes_same_timestamp_prefix" {
  command = plan

  assert {
    condition     = aws_memorydb_cluster.this[0].name == "ona-runner-2ec33d556332a866-memorydb"
    error_message = "resource names must use a hash of the full runner ID"
  }
}

run "second_runner_id_with_same_timestamp_prefix" {
  command = plan

  variables {
    runner_id = "019d6999-807c-7000-8000-000000000001"
  }

  assert {
    condition     = aws_memorydb_cluster.this[0].name == "ona-runner-af821ead46c406c7-memorydb"
    error_message = "runner IDs with the same UUIDv7 timestamp prefix must generate different resource names"
  }
}

run "truncated_runner_name_does_not_create_consecutive_hyphens" {
  command = plan

  variables {
    runner_name = "abcdefghijk-lmnop"
  }

  assert {
    condition     = aws_memorydb_cluster.this[0].name == "abcdefghijk-2ec33d556332a866-memorydb"
    error_message = "the truncated runner name must not end with a hyphen before the ID suffix"
  }
}

run "resource_name_prefix_rejects_consecutive_hyphens" {
  command = plan

  variables {
    resource_name_prefix = "invalid--prefix"
  }

  expect_failures = [var.resource_name_prefix]
}
