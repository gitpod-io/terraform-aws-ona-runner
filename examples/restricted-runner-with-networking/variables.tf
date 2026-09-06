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

variable "runner_name" {
  description = "Human-readable runner name used in AWS resource names."
  type        = string
  default     = "ona-runner"

  validation {
    condition     = can(regex("^[A-Za-z]([A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.runner_name)) && !can(regex("--", var.runner_name))
    error_message = "runner_name must be 1-32 characters, start with a letter, end with a letter or number, contain only letters, numbers, and hyphens, and not contain consecutive hyphens."
  }
}

variable "availability_zones" {
  description = "Two or three availability zones in which to create each subnet tier."
  type        = list(string)

  validation {
    condition     = contains([2, 3], length(var.availability_zones)) && length(distinct(var.availability_zones)) == length(var.availability_zones) && alltrue([for zone in var.availability_zones : trimspace(zone) != ""])
    error_message = "availability_zones must contain two or three distinct, non-empty availability zones."
  }
}

variable "network_name" {
  description = "Optional name prefix for networking resources. When null, derives a unique prefix from runner_name and runner_id."
  type        = string
  default     = null

  validation {
    condition     = var.network_name == null || (can(regex("^[a-z]([a-z0-9-]{0,30}[a-z0-9])?$", var.network_name)) && !can(regex("--", var.network_name)))
    error_message = "network_name must be 1-32 lowercase letters, numbers, or hyphens; start with a letter; end with a letter or number; and not contain consecutive hyphens."
  }
}

variable "routable_vpc_cidr" {
  description = "Primary VPC CIDR used for firewall and NAT Gateway or Transit Gateway attachment subnets."
  type        = string

  validation {
    condition = (
      can(cidrnetmask(var.routable_vpc_cidr)) &&
      try(tonumber(split("/", var.routable_vpc_cidr)[1]) >= 16, false) &&
      try(tonumber(split("/", var.routable_vpc_cidr)[1]) <= 24, false) &&
      !can(regex("^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.", var.routable_vpc_cidr))
    )
    error_message = "routable_vpc_cidr must be a valid IPv4 CIDR between /16 and /24 and must not overlap the 100.64.0.0/10 CGNAT range."
  }
}

variable "runner_cgnat_cidr" {
  description = "Secondary /16 VPC CIDR from 100.64.0.0/10. The first half is allocated to runner subnets and the second half is reserved."
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(regex("^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.0\\.0/16$", var.runner_cgnat_cidr))
    error_message = "runner_cgnat_cidr must be an aligned /16 within 100.64.0.0/10."
  }
}

variable "enable_firewall" {
  description = "Whether to inspect runner egress with AWS Network Firewall. Disabling inspection is supported but not recommended."
  type        = bool
  default     = true
}

variable "egress" {
  description = "Egress path. NAT mode creates gateways and internet connectivity; Transit Gateway mode creates a VPC attachment and enables appliance mode when the firewall is enabled."
  type = object({
    mode               = string
    transit_gateway_id = optional(string)
  })
  default = {
    mode = "nat_gateway"
  }

  validation {
    condition = (
      (var.egress.mode == "nat_gateway" && try(trimspace(var.egress.transit_gateway_id), "") == "") ||
      (var.egress.mode == "transit_gateway" && can(regex("^tgw-[0-9a-f]+$", var.egress.transit_gateway_id)))
    )
    error_message = "egress.mode must be nat_gateway without a transit_gateway_id, or transit_gateway with a valid tgw-* ID."
  }
}

variable "firewall_policy_arn" {
  description = "Existing Network Firewall policy ARN. When null and enable_firewall is true, the example creates a permissive inspection policy that alerts on established flows."
  type        = string
  default     = null

  validation {
    condition     = var.firewall_policy_arn == null || can(regex("^arn:[^:]+:network-firewall:[^:]+:[0-9]{12}:firewall-policy/.+$", var.firewall_policy_arn))
    error_message = "firewall_policy_arn must be null or a Network Firewall policy ARN."
  }
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for VPC, Network Firewall, and Resolver query logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a retention period supported by CloudWatch Logs."
  }
}

variable "log_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for CloudWatch log groups. Its key policy must permit the logging services used by this example."
  type        = string
  default     = null

  validation {
    condition     = var.log_kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be null or a KMS key ARN."
  }
}

variable "tags" {
  description = "Tags to apply to supported AWS resources."
  type        = map(string)
  default     = {}
}
