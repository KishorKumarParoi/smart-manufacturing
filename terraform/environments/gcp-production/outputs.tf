output "cluster_name" {
  description = "Production GKE Cluster Name"
  value       = google_container_cluster.production.name
}

output "cluster_endpoint" {
  description = "GKE Master Endpoint IP"
  value       = google_container_cluster.production.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE Cluster Root Certificate"
  value       = google_container_cluster.production.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "get_credentials_command" {
  description = "Command to configure kubectl context"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.production.name} --zone ${var.zone} --project ${var.project_id}"
}
