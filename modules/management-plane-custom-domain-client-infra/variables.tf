variable "vpc_id" {
  description = "VPC where the custom-domain Network Load Balancer and VPC endpoint are created."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the Network Load Balancer and VPC endpoint. Provide subnets in at least two Availability Zones."
  type        = set(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets."
  }
}

variable "domain_name" {
  description = "Custom Ona management-plane domain, for example ona.example.com."
  type        = string

  validation {
    condition     = trimspace(var.domain_name) != "" && !startswith(var.domain_name, "vscode.")
    error_message = "domain_name must be a non-empty base domain without the vscode prefix."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN covering domain_name and vscode.domain_name. The certificate must be in the deployment region."
  type        = string
}

variable "allowed_ipv4_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed to connect to the Network Load Balancer on port 443."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_ipv4_cidr_blocks : can(cidrnetmask(cidr))])
    error_message = "allowed_ipv4_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect to the Network Load Balancer on port 443."
  type        = set(string)
  default     = []
}

variable "load_balancer_scheme" {
  description = "Network Load Balancer scheme. Use internal for private connectivity or internet-facing for public access."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["internal", "internet-facing"], var.load_balancer_scheme)
    error_message = "load_balancer_scheme must be either internal or internet-facing."
  }
}

variable "endpoint_service_name" {
  description = "Ona relay VPC endpoint service name. Override only for a non-production relay deployment."
  type        = string
  default     = "com.amazonaws.vpce.us-east-1.vpce-svc-00fa18d41fdd25cad"
}

variable "endpoint_service_region" {
  description = "AWS region hosting the Ona relay VPC endpoint service."
  type        = string
  default     = "us-east-1"
}

variable "service_name" {
  description = "Name prefix for resources created by this module."
  type        = string
  default     = "ona-custom-domain"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,22}[a-zA-Z0-9])?$", var.service_name)) && !can(regex("--", var.service_name))
    error_message = "service_name must be 1-24 letters, numbers, or hyphens; start and end with a letter or number; and not contain consecutive hyphens."
  }
}

variable "tags" {
  description = "Tags to apply to supported AWS resources."
  type        = map(string)
  default     = {}
}
