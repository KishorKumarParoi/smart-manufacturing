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
  zone    = var.zone
}

# 1. Firewall rules for DevOps tools
resource "google_compute_firewall" "devops_ports" {
  name    = "allow-devops-platform"
  network = "default"

  allow {
    protocol = "tcp"
    ports = [
      "22",          # SSH
      "80",          # HTTP
      "443",         # HTTPS
      "8000",        # Smart Manufacturing API
      "8080",        # Jenkins Web UI
      "8081",        # Nexus Repository
      "9000",        # SonarQube
      "30080",       # ArgoCD Web UI NodePort
      "30751",       # ArgoCD Web HTTP NodePort
      "30752",       # ArgoCD Web HTTPS NodePort
      "50000",       # Jenkins Agent JNLP
      "30000-32767"  # Kubernetes NodePort Range
    ]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-devops-platform", "devops-control-plane", "devops-vm"]
}

# 2. GCP Compute VM Instance
resource "google_compute_instance" "devops_node" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["allow-devops-platform", "devops-control-plane", "devops-vm", "http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    access_config {
      // Ephemeral external IP
    }
  }

  metadata = {
    startup-script = file("${path.module}/../../../scripts/setup-devops-vm.sh")
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}

output "instance_name" {
  value = google_compute_instance.devops_node.name
}

output "external_ip" {
  value = google_compute_instance.devops_node.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.devops_node.name} --zone ${var.zone}"
}

output "jenkins_url" {
  value = "http://${google_compute_instance.devops_node.network_interface[0].access_config[0].nat_ip}:8080"
}

output "sonarqube_url" {
  value = "http://${google_compute_instance.devops_node.network_interface[0].access_config[0].nat_ip}:9000"
}

output "nexus_url" {
  value = "http://${google_compute_instance.devops_node.network_interface[0].access_config[0].nat_ip}:8081"
}

output "argocd_url" {
  value = "http://${google_compute_instance.devops_node.network_interface[0].access_config[0].nat_ip}:30080"
}
