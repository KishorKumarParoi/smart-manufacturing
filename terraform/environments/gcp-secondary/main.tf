terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "gcp_secondary_cluster" {
  source          = "../../modules/gcp_gke_gpu"
  cluster_name    = var.cluster_name
  region          = var.region
  gpu_type        = var.gpu_type
  gcs_bucket_name = var.gcs_bucket_name
}

output "gke_cluster_name" {
  value = module.gcp_secondary_cluster.cluster_name
}

output "gke_cluster_endpoint" {
  value = module.gcp_secondary_cluster.cluster_endpoint
}

output "artifact_bucket" {
  value = module.gcp_secondary_cluster.gcs_bucket
}
