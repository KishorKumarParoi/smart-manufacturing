variable "cluster_name" {
  type    = string
  default = "smart-mfg-gke-failover"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "gpu_type" {
  type    = string
  default = "nvidia-tesla-t4"
}

variable "gcs_bucket_name" {
  type    = string
  default = "smart-mfg-mlops-artifacts-us-central1"
}
