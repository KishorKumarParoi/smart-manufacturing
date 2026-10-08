terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "aws_primary_cluster" {
  source               = "../../modules/aws_eks_gpu"
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  gpu_instance_type    = var.gpu_instance_type
  artifact_bucket_name = var.artifact_bucket_name
}

output "eks_cluster_name" {
  value = module.aws_primary_cluster.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.aws_primary_cluster.cluster_endpoint
}

output "artifact_bucket" {
  value = module.aws_primary_cluster.s3_bucket
}
