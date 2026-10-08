variable "hosted_zone_id" {
  type        = string
  description = "AWS Route53 Hosted Zone ID"
}

variable "domain_name" {
  type        = string
  default     = "api.smartmfg.ai"
  description = "Global unified inference domain name"
}

variable "primary_endpoint_fqdn" {
  type        = string
  description = "Primary AWS ingress hostname"
}

variable "secondary_endpoint_fqdn" {
  type        = string
  description = "Secondary GCP ingress hostname"
}
