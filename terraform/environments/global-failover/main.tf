terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "global_failover" {
  source                  = "../../modules/global_dns_failover"
  hosted_zone_id          = var.hosted_zone_id
  domain_name             = var.domain_name
  primary_endpoint_fqdn   = var.primary_endpoint_fqdn
  secondary_endpoint_fqdn = var.secondary_endpoint_fqdn
}

output "global_domain" {
  value = module.global_failover.global_domain
}

output "health_check_id" {
  value = module.global_failover.health_check_id
}
