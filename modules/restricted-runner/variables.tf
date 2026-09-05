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

variable "vpc_id" {
  description = "VPC ID where the runner infrastructure is deployed."
  type        = string
}

variable "runner_subnet_ids" {
  description = "Subnet IDs for ECS runner instances and cache resources."
  type        = list(string)
}
