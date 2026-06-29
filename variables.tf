variable "runner_id" {
  description = "The Ona runner ID."
  type        = string
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

variable "bottlerocket_ami_id" {
  description = "Optional Bottlerocket ECS AMI ID for runner ECS hosts. Leave empty to resolve the latest AWS-managed Bottlerocket AMI from SSM."
  type        = string
  default     = ""
}

variable "runner_image" {
  description = "Container image for the EC2 runner."
  type        = string
  default     = "public.ecr.aws/k5t9d3j5/application/gitpod-next/gitpod-ec2-runner:__EC2_RUNNER_VERSION__"
}

variable "proxy_image" {
  description = "Container image for the runner proxy."
  type        = string
  default     = "public.ecr.aws/k5t9d3j5/application/gitpod-next/gitpod-proxy:__EC2_RUNNER_VERSION__"
}

variable "prometheus_image" {
  description = "Container image for the Prometheus sidecar."
  type        = string
  default     = "prom/prometheus:v3.2.1"
}

variable "node_exporter_image" {
  description = "Container image for the node-exporter sidecar."
  type        = string
  default     = "prom/node-exporter:v1.9.1"
}

variable "development_version" {
  description = "Optional development version passed to the runner."
  type        = string
  default     = ""
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
