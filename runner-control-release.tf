locals {
  runner_iam_managed       = var.runner_iam_phase != "legacy"
  runner_iam_prepare       = var.runner_iam_phase == "prepare"
  runner_iam_cutover       = var.runner_iam_phase == "cutover"
  runner_iam_confined      = var.runner_iam_phase == "confined"
  runner_releases_base_url = trimsuffix(var.runner_releases_url, "/")
  runner_manifest_url      = "${local.runner_releases_base_url}/ec2/releases/${var.runner_template_build_version}/manifest.json"
}

data "http" "runner_release_manifest" {
  count = local.runner_iam_managed ? 1 : 0
  url   = local.runner_manifest_url

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  runner_release_manifest = local.runner_iam_managed ? try(jsondecode(one(data.http.runner_release_manifest).response_body), null) : null
  runner_template_url = try(
    local.runner_release_manifest.cloudformation_template_url,
    "${local.runner_releases_base_url}/invalid-runner-template",
  )
  expected_runner_template_url = "${local.runner_releases_base_url}/ec2/releases/${var.runner_template_build_version}/gitpod-ec2-runner-enterprise-fargate-private-ecr.json"
  runner_control_advertised = local.runner_iam_managed && (
    can(local.runner_release_manifest.runner_control_protocol) ||
    can(local.runner_release_manifest.runner_control_source_sha256)
  )
  runner_control_protocol_is_valid = try(local.runner_release_manifest.runner_control_protocol == 1, false)
  runner_control_source_digest     = try(local.runner_release_manifest.runner_control_source_sha256, "")
  capable_runner_release = local.runner_iam_managed && (
    try(local.runner_release_manifest.version, "") == var.runner_template_build_version &&
    local.runner_control_advertised &&
    local.runner_control_protocol_is_valid &&
    can(regex("^sha256:[0-9a-f]{64}$", local.runner_control_source_digest)) &&
    can(regex("@sha256:[0-9a-f]{64}$", try(local.runner_release_manifest.image_digest, ""))) &&
    can(regex("@sha256:[0-9a-f]{64}$", try(local.runner_release_manifest.proxy_image_digest, ""))) &&
    local.runner_template_url == local.expected_runner_template_url
  )
}

data "http" "runner_release_template" {
  count = local.runner_iam_managed ? 1 : 0
  url   = local.expected_runner_template_url

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  runner_release_template = local.runner_iam_managed ? try(jsondecode(one(data.http.runner_release_template).response_body), {}) : {}
  runner_control_resources = local.runner_iam_managed ? [
    for resource in try(local.runner_release_template.Resources, {}) : resource
    if try(resource.Type, "") == "AWS::Lambda::Function" &&
    try(resource.Properties.Handler, "") == "index.handler" &&
    try(resource.Properties.Code.ZipFile, "") != ""
  ] : []
  runner_control_source = length(local.runner_control_resources) == 1 ? try(one(local.runner_control_resources).Properties.Code.ZipFile, "") : ""
  runner_control_source_is_valid = (
    length(local.runner_control_resources) == 1 &&
    "sha256:${sha256(local.runner_control_source)}" == local.runner_control_source_digest
  )
  runner_control_approved_image_ids = length(local.runner_control_resources) == 1 ? try(
    one(local.runner_control_resources).Properties.Environment.Variables.APPROVED_IMAGE_IDS,
    "",
  ) : ""
}

data "archive_file" "runner_control" {
  count       = local.runner_iam_managed ? 1 : 0
  type        = "zip"
  output_path = "${path.root}/.terraform/runner-control-${substr(sha256(local.runner_control_source), 0, 16)}.zip"

  source {
    content  = local.runner_control_source
    filename = "index.js"
  }
}
