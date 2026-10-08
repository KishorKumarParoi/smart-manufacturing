variable "project_id" {
  type        = string
  default     = "project-53d8ce01-b0e0-4f8b-94c"
  description = "GCP Project ID"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "instance_name" {
  type    = string
  default = "devops-control-plane"
}

variable "machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = "4 vCPU, 16 GB RAM (optimal for Jenkins + SonarQube + Nexus + K8s)"
}

variable "disk_size_gb" {
  type    = number
  default = 100
  description = "Boot disk size in GB (Nexus & Docker images require 50-100GB)"
}
