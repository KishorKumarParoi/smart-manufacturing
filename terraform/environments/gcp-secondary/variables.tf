variable "project_id" {
  type    = string
  default = "smart-mfg-enterprise-prod"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "cluster_name" {
  type    = string
  default = "smart-mfg-gke-failover"
}

variable "gpu_type" {
  type    = string
  default = "nvidia-tesla-t4"
}

variable "gcs_bucket_name" {
  type    = string
  default = "smart-mfg-mlops-artifacts-us-central1"
}
