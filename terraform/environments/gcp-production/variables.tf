variable "project_id" {
  type        = string
  description = "Google Cloud Project ID"
  default     = "project-53d8ce01-b0e0-4f8b-94c"
}

variable "region" {
  type        = string
  description = "Google Cloud Region"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "Google Cloud Primary Zone"
  default     = "us-central1-a"
}

variable "cluster_name" {
  type        = string
  description = "Production GKE Cluster Name"
  default     = "smart-mfg-prod-gke"
}

variable "gpu_type" {
  type        = string
  description = "Accelerator GPU Type"
  default     = "nvidia-tesla-t4"
}

variable "authorized_ipv4_cidr_blocks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "Master authorized network CIDRs allowed to access the Kubernetes API server"
  default = [
    {
      cidr_block   = "35.235.240.0/20"
      display_name = "Google Cloud IAP"
    },
    {
      cidr_block   = "203.31.169.0/24"
      display_name = "Admin Carrier Subnet"
    }
  ]
}
