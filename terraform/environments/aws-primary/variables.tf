variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "smart-mfg-eks-primary"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "gpu_instance_type" {
  type    = string
  default = "g4dn.xlarge"
}

variable "artifact_bucket_name" {
  type    = string
  default = "smart-mfg-mlops-artifacts-us-east-1"
}
