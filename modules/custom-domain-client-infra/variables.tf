variable "domain_name" {
  description = "Runner domain name, for example runner.example.com."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID that contains domain_name."
  type        = string
}

variable "load_balancer_dns_name" {
  description = "Runner Network Load Balancer DNS name. Leave empty when only creating the certificate."
  type        = string
  default     = ""
}

variable "load_balancer_zone_id" {
  description = "Runner Network Load Balancer canonical hosted zone ID. Required when load_balancer_dns_name is set."
  type        = string
  default     = ""
}

variable "create_alias_records" {
  description = "Whether to create Route53 alias records for domain_name and *.domain_name."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to supported AWS resources."
  type        = map(string)
  default     = {}
}
