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

variable "api_endpoint" {
  description = "Ona management plane API endpoint."
  type        = string
  default     = "https://app.gitpod.io/api"
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

variable "vpc_id" {
  description = "VPC ID where the runner infrastructure is deployed."
  type        = string
}

variable "runner_subnet_ids" {
  description = "Subnet IDs for ECS runner instances and cache resources."
  type        = list(string)
}

variable "proxy_config" {
  description = "Outbound proxy settings. Unset fields use the root runner module's defaults."
  type = object({
    http_proxy  = optional(string)
    https_proxy = optional(string)
    all_proxy   = optional(string)
    no_proxy    = optional(string)
  })
  default = {}
}

variable "custom_ca_trust_bundle" {
  description = "Optional custom CA trust bundle content or URL understood by the runner."
  type        = string
  default     = ""
}

variable "pre_created_iam_roles" {
  description = "Existing IAM role ARNs for a new runner. Omitted roles are created and fully configured. attach_iam_policies manages permission policies on supplied roles only; trust, tags, and boundaries remain customer-owned. The proxy value is ignored when restrict_ingress is true."
  type = object({
    ecs_execution                      = optional(string)
    ecs_task                           = optional(string)
    proxy                              = optional(string)
    adot                               = optional(string)
    environment                        = optional(string)
    s3_access                          = optional(string)
    devcontainer_cache_registry_access = optional(string)
    attach_iam_policies                = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "environment_instance_profile_name" {
  description = "Existing instance profile containing the supplied environment role. Requires pre_created_iam_roles.environment. When null, a profile is created around the effective environment role, independently of attach_iam_policies."
  type        = string
  default     = null
}
