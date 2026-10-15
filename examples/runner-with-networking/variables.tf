variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "runner_id" {
  description = "Ona runner ID."
  type        = string
}

variable "runner_token" {
  description = "Ona runner token."
  type        = string
  sensitive   = true
}

variable "runner_domain" {
  description = "Runner custom domain."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for runner_domain."
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC ID."
  type        = string
}

variable "runner_subnet_ids" {
  description = "Existing subnet IDs for runner ECS instances."
  type        = list(string)
}

variable "load_balancer_subnet_ids" {
  description = "Existing subnet IDs for the Network Load Balancer."
  type        = list(string)
}

variable "restrict_ingress" {
  description = "Whether to restrict inbound network access to runner and environment infrastructure."
  type        = bool
  default     = false
}

variable "internal_llm_proxy_port" {
  description = "Port for direct environment-to-runner LLM proxy traffic when restricted ingress is enabled."
  type        = number
  default     = 8089
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
