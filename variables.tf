variable "runner_id" {
  description = "The Ona runner ID."
  type        = string

  validation {
    condition     = trimspace(var.runner_id) != ""
    error_message = "runner_id must not be empty."
  }
}

variable "runner_token" {
  description = "The Ona runner exchange token."
  type        = string
  sensitive   = true
}

variable "runner_name" {
  description = "Human-readable runner name used in AWS resource names."
  type        = string
  default     = "ona-runner"

  validation {
    condition     = can(regex("^[A-Za-z]([A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.runner_name)) && !can(regex("--", var.runner_name))
    error_message = "runner_name must be 1-32 characters, start with a letter, end with a letter or number, contain only letters, numbers, and hyphens, and not contain consecutive hyphens."
  }
}

variable "resource_name_prefix" {
  description = "Optional legacy AWS resource-name prefix. Leave unset to derive a unique prefix from runner_name and runner_id."
  type        = string
  default     = null

  validation {
    condition     = var.resource_name_prefix == null || (can(regex("^[a-z]([a-z0-9-]{0,30}[a-z0-9])?$", var.resource_name_prefix)) && !can(regex("--", var.resource_name_prefix)))
    error_message = "resource_name_prefix must be 1-32 lowercase letters, numbers, or hyphens; it must start with a letter, end with a letter or number, and not contain consecutive hyphens."
  }
}

variable "api_endpoint" {
  description = "Ona management plane API endpoint."
  type        = string
  default     = "https://app.gitpod.io/api"
}

variable "gateway_api_endpoint" {
  description = "Gateway API endpoint. Leave empty for the default Ona gateway behavior."
  type        = string
  default     = ""
}

variable "runner_domain" {
  description = "Domain name used by the runner proxy."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the runner proxy Network Load Balancer TLS listener."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the runner infrastructure is deployed."
  type        = string
}

variable "runner_subnet_ids" {
  description = "Subnet IDs for ECS runner instances and cache resources."
  type        = list(string)
}

variable "load_balancer_subnet_ids" {
  description = "Subnet IDs for the runner proxy Network Load Balancer."
  type        = list(string)
}

variable "load_balancer_scheme" {
  description = "Network Load Balancer scheme."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["internal", "internet-facing"], var.load_balancer_scheme)
    error_message = "load_balancer_scheme must be either internal or internet-facing."
  }
}

variable "load_balancer_security_group_id" {
  description = "Optional existing security group for the Network Load Balancer. When empty, the module creates one."
  type        = string
  default     = ""
}

variable "runner_size" {
  description = "Runner infrastructure size."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "large"], var.runner_size)
    error_message = "runner_size must be small or large."
  }
}

variable "cache_engine" {
  description = "Cache engine for AI execution data."
  type        = string
  default     = "MemoryDB"

  validation {
    condition     = contains(["MemoryDB", "ElastiCache"], var.cache_engine)
    error_message = "cache_engine must be MemoryDB or ElastiCache."
  }
}

variable "default_ami" {
  description = "Default AMI for environments launched by the runner. Leave empty to use runner defaults."
  type        = string
  default     = ""
}

variable "runner_image" {
  description = "Tested container image for the runner. Obtain it from the runner release manifest."
  type        = string

  validation {
    condition     = trimspace(var.runner_image) != "" && !strcontains(var.runner_image, "__")
    error_message = "runner_image must be a tested, resolved image reference without placeholder tokens."
  }
}

variable "proxy_image" {
  description = "Tested container image for the runner proxy. Obtain it from the same runner release manifest as runner_image."
  type        = string

  validation {
    condition     = trimspace(var.proxy_image) != "" && !strcontains(var.proxy_image, "__")
    error_message = "proxy_image must be a tested, resolved image reference without placeholder tokens."
  }
}

variable "private_ecr_prefix" {
  description = "Private ECR registry prefix from the runner release manifest."
  type        = string

  validation {
    condition     = trimspace(var.private_ecr_prefix) != "" && !strcontains(var.private_ecr_prefix, "__")
    error_message = "private_ecr_prefix must be a resolved registry prefix without placeholder tokens."
  }
}

variable "adot_image" {
  description = "Container image for the AWS Distro for OpenTelemetry collector."
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.43.3"
}

variable "metrics_audit_sync_image" {
  description = "Container image for the metrics audit S3 sync sidecar."
  type        = string
  default     = "public.ecr.aws/aws-cli/aws-cli:2.27.22@sha256:1d5753647df57828762601f4d82790f3441060dbc8671cd01c52df05cfd3b2c7"
}

variable "assign_public_ip" {
  description = "Assign public IP addresses to the Fargate runner, proxy, and ADOT tasks. Use only when the runner subnets have internet-gateway egress."
  type        = bool
  default     = false
}

variable "permissions_boundary_arn" {
  description = "Optional IAM permissions boundary applied to every runner-managed role. Set this to the enterprise boundary approved for the AWS account."
  type        = string
  default     = null
}

variable "development_version" {
  description = "Optional development version passed to the runner."
  type        = string
  default     = ""
}

variable "runner_template_build_version" {
  description = "Runner template build version from the same runner release manifest as the container images."
  type        = string

  validation {
    condition     = trimspace(var.runner_template_build_version) != "" && !strcontains(var.runner_template_build_version, "__")
    error_message = "runner_template_build_version must be a resolved release version without placeholder tokens."
  }
}

variable "proxy_config" {
  description = "HTTP proxy settings for runner containers and Bottlerocket hosts."
  type = object({
    http_proxy  = optional(string, "")
    https_proxy = optional(string, "")
    all_proxy   = optional(string, "")
    no_proxy    = optional(string, "localhost,127.0.0.1,.internal,.amazonaws.com,169.254.0.0/16,app.gitpod.io")
  })
  default = {}
}

variable "custom_ca_trust_bundle" {
  description = "Optional custom CA trust bundle content or URL understood by the runner."
  type        = string
  default     = ""
}

variable "disable_resource_policies" {
  description = "Disable restrictive read-scoping S3 and DynamoDB resource policies. TLS-only S3 policies remain enabled unless disable_s3_tls_enforcement is true."
  type        = bool
  default     = false
}

variable "disable_s3_tls_enforcement" {
  description = "Disable S3 bucket policies that deny non-TLS requests. Intended only for organizations that cannot use S3 bucket policies."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to AWS resources."
  type        = map(string)
  default     = {}
}
