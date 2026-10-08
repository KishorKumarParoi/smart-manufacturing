variable "hosted_zone_id" {
  type    = string
  default = "Z1001234ABCXYZEXAMPLE"
}

variable "domain_name" {
  type    = string
  default = "api.smartmfg.ai"
}

variable "primary_endpoint_fqdn" {
  type    = string
  default = "k8s-aws-us-east-1-alb.smartmfg.internal"
}

variable "secondary_endpoint_fqdn" {
  type    = string
  default = "k8s-gcp-us-central1-ingress.smartmfg.internal"
}
