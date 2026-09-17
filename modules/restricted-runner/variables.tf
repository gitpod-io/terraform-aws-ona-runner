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

variable "runner_iam_phase" {
  description = "Runner IAM migration phase forwarded to the root runner module."
  type        = string
  default     = "legacy"

  validation {
    condition     = contains(["legacy", "prepare", "cutover", "confined"], var.runner_iam_phase)
    error_message = "runner_iam_phase must be legacy, prepare, cutover, or confined."
  }
}

variable "runner_iam_retirement_confirmed" {
  description = "Confirms legacy task and role-session retirement before the confined phase."
  type        = bool
  default     = false
}

variable "runner_releases_url" {
  description = "Trusted base URL for immutable runner release manifests and templates."
  type        = string
  default     = "https://releases.gitpod.io"
}
