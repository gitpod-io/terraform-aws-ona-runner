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

variable "runner_image" {
  description = "Tested runner image from the runner release manifest."
  type        = string
}

variable "proxy_image" {
  description = "Tested runner proxy image from the same runner release manifest."
  type        = string
}

variable "runner_template_build_version" {
  description = "Runner template build version from the runner release manifest."
  type        = string
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
