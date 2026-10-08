terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

# 1. Route 53 Health Check for Primary AWS EKS Inference Ingress
resource "aws_route53_health_check" "primary_health" {
  fqdn              = var.primary_endpoint_fqdn
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 10

  tags = {
    Name = "smart-mfg-primary-aws-health-check"
  }
}

# 2. Global DNS Failover Records (Primary = AWS, Secondary = GCP)
resource "aws_route53_record" "primary" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 30

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier = "primary-aws-eks-us-east-1"
  records        = [var.primary_endpoint_fqdn]
  health_check_id = aws_route53_health_check.primary_health.id
}

resource "aws_route53_record" "secondary" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 30

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary-gcp-gke-us-central1"
  records        = [var.secondary_endpoint_fqdn]
}
