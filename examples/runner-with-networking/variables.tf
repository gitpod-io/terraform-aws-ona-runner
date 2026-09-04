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
  description = "Runner custom domain. Required for standard ingress."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for runner_domain. Required for standard ingress."
  type        = string
  default     = null
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
  description = "Existing subnet IDs for the Network Load Balancer. Required for standard ingress."
  type        = list(string)
  default     = []
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
