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

run "public_access_block_is_managed_by_default" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_s3_bucket_public_access_block.container_registry) == 1,
      length(aws_s3_bucket_public_access_block.logs) == 1,
      length(aws_s3_bucket_public_access_block.agent) == 1,
    ])
    error_message = "the module must manage Public Access Block for every S3 bucket by default."
  }
}

run "public_access_block_can_be_managed_externally" {
  command = plan

  variables {
    manage_s3_bucket_public_access_block = false
  }

  assert {
    condition = alltrue([
      length(aws_s3_bucket_public_access_block.container_registry) == 0,
      length(aws_s3_bucket_public_access_block.logs) == 0,
      length(aws_s3_bucket_public_access_block.agent) == 0,
    ])
    error_message = "the module must omit every Public Access Block resource when external management is selected."
  }
}
