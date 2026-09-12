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

variable "runner_domain" {
  description = "Domain name used by the runner proxy. Required unless restrict_ingress is true."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the runner proxy Network Load Balancer TLS listener. Required unless restrict_ingress is true."
  type        = string
  default     = null
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
  description = "Subnet IDs for the runner proxy Network Load Balancer. Required unless restrict_ingress is true."
  type        = list(string)
  default     = []
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

variable "runner_image" {
  description = "Optional custom runner image. Leave empty to use the image derived from runner_template_build_version."
  type        = string
  default     = ""

  validation {
    condition     = !strcontains(var.runner_image, "__")
    error_message = "runner_image must not contain placeholder tokens."
  }
}

variable "proxy_image" {
  description = "Optional custom runner proxy image. Leave empty to use the image derived from runner_template_build_version."
  type        = string
  default     = ""

  validation {
    condition     = !strcontains(var.proxy_image, "__")
    error_message = "proxy_image must not contain placeholder tokens."
  }
}

variable "assign_public_ip" {
  description = "Assign public IP addresses to the Fargate runner, proxy, and ADOT tasks. Use only when the runner subnets have internet-gateway egress."
  type        = bool
  default     = false
}

variable "restrict_ingress" {
  description = "Whether to restrict inbound network access to runner and environment infrastructure."
  type        = bool
  default     = false
}

variable "internal_llm_proxy_port" {
  description = "Port for direct environment-to-runner LLM proxy traffic when restrict_ingress is enabled."
  type        = number
  default     = 8089

  validation {
    condition = (
      var.internal_llm_proxy_port == floor(var.internal_llm_proxy_port) &&
      var.internal_llm_proxy_port >= 1 &&
      var.internal_llm_proxy_port <= 65535 &&
      !contains([7070, 7071, 8081, 9090, 9091], var.internal_llm_proxy_port)
    )
    error_message = "internal_llm_proxy_port must be an integer between 1 and 65535 and must not conflict with runner ports 7070, 7071, 8081, 9090, or 9091."
  }
}

variable "manage_s3_bucket_public_access_block" {
  description = "Manage bucket-level S3 Public Access Block settings for the container registry, logs, and agent buckets. Disable only when equivalent protection is enforced outside this module."
  type        = bool
  default     = true
}

variable "runner_template_build_version" {
  description = "Runner template build version from the same runner release manifest as the container images."
  type        = string
  default     = "20260912.604"

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

variable "tags" {
  description = "Tags to apply to AWS resources."
  type        = map(string)
  default     = {}
}
