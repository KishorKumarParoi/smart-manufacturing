output "global_domain" {
  value = var.domain_name
}

output "health_check_id" {
  value = aws_route53_health_check.primary_health.id
}
