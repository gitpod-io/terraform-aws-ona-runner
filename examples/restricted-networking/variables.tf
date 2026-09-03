variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "availability_zones" {
  description = "Two or three availability zones for the runner deployment."
  type        = list(string)
}

variable "network_name" {
  description = "Name prefix for networking resources."
  type        = string
  default     = "ona-runner-network"
}

variable "routable_vpc_cidr" {
  description = "Primary VPC CIDR used for firewall and NAT Gateway or Transit Gateway attachment subnets."
  type        = string
}

variable "runner_cgnat_cidr" {
  description = "Secondary /16 VPC CIDR from 100.64.0.0/10 for runner instances."
  type        = string
  default     = "100.64.0.0/16"
}

variable "enable_firewall" {
  description = "Whether to inspect runner egress with AWS Network Firewall."
  type        = bool
  default     = true
}

variable "egress" {
  description = "Egress mode and optional Transit Gateway ID."
  type = object({
    mode               = string
    transit_gateway_id = optional(string)
  })
  default = {
    mode = "nat_gateway"
  }
}

variable "firewall_policy_arn" {
  description = "Optional existing Network Firewall policy ARN."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for network telemetry."
  type        = number
  default     = 30
}

variable "log_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for network log groups."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to supported AWS resources."
  type        = map(string)
  default     = {}
}
