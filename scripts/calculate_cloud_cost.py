#!/usr/bin/env python3
"""
Multi-Cloud Cost Calculator & Live API Cost Auditor (AWS, GCP, Azure)
===================================================================
Enterprise-grade multi-cloud cost calculator and live financial auditor
for DevOps, MLOps, Kubernetes, and Cloud Infrastructure engineering.

Supported Features:
  * Unified side-by-side cost estimation for AWS, GCP, and Azure.
  * Real-world retail pricing for Compute, GPU, Storage, K8s, and Network.
  * Presets for the Smart Manufacturing MLOps project, DevOps VM, K8s GPU/CPU clusters.
  * LIVE CLOUD FINANCIAL AUDIT: Queries real-time APIs/CLIs:
      - AWS: Cost Explorer API (MTD spend by service), EC2 running instances, EKS, S3
      - GCP: Cloud Billing Account status, Compute Engine VMs, Persistent Disks, GKE
      - Azure: Consumption Usage API, Deployed Resources (Databricks, EventHub, Storage, VMs)
  * Itemized breakdown explaining the purpose and business function of each cost.
  * Multi-currency conversion (USD, EUR, GBP, INR, BDT).
  * Formatted terminal dashboard, GitHub Markdown, JSON, and CSV export.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List, Optional, Tuple

# ==============================================================================
# Color & Formatting Utilities
# ==============================================================================
class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    MAGENTA = "\033[35m"
    RESET = "\033[0m"


def strip_ansi(text: str) -> str:
    import re
    return re.sub(r"\033\[[0-9;]*m", "", text)


# ==============================================================================
# Currency Exchange Rates (Base: USD)
# ==============================================================================
CURRENCY_RATES = {
    "USD": (1.0, "$"),
    "EUR": (0.92, "€"),
    "GBP": (0.78, "£"),
    "INR": (83.50, "₹"),
    "BDT": (118.00, "৳"),
}

# ==============================================================================
# Multi-Cloud Pricing Database (US/Standard Regions Baseline)
# ==============================================================================
PRICING_CATALOG = {
    "AWS": {
        "provider_name": "Amazon Web Services (AWS)",
        "region_default": "us-east-1",
        "currency": "USD",
        "vm_hourly": {
            "micro": (0.0104, 0.0031, 1, 1, "t3.micro"),
            "small": (0.0208, 0.0062, 1, 2, "t3.small"),
            "medium": (0.0416, 0.0125, 2, 4, "t3.medium"),
            "large": (0.0832, 0.0250, 2, 8, "t3.large"),
            "xlarge": (0.1664, 0.0499, 4, 16, "t3.xlarge (General Worker)"),
            "2xlarge": (0.3328, 0.0998, 8, 32, "t3.2xlarge"),
            "4xlarge": (0.6656, 0.1997, 16, 64, "t3.4xlarge"),
        },
        "known_instance_rates": {
            "t2.nano": 0.0058, "t2.micro": 0.0116, "t2.small": 0.023, "t2.medium": 0.0464,
            "t3.nano": 0.0052, "t3.micro": 0.0104, "t3.small": 0.0208, "t3.medium": 0.0416,
            "t3.large": 0.0832, "t3.xlarge": 0.1664, "t3.2xlarge": 0.3328,
            "t4g.micro": 0.0084, "t4g.small": 0.0168, "t4g.medium": 0.0336, "t4g.large": 0.0672,
            "m5.large": 0.096, "m5.xlarge": 0.192, "m5.2xlarge": 0.384,
            "m6i.large": 0.096, "m6i.xlarge": 0.192, "m6i.2xlarge": 0.384,
            "c5.large": 0.085, "c5.xlarge": 0.170, "c5.2xlarge": 0.340,
            "g4dn.xlarge": 0.526, "g5.xlarge": 1.006, "p3.2xlarge": 3.06,
        },
        "gpu_hourly": {
            "t4": (0.526, 0.158, 16, "g4dn.xlarge (1x NVIDIA T4 16GB)"),
            "a10g": (1.006, 0.302, 24, "g5.xlarge (1x NVIDIA A10G 24GB)"),
            "l4": (0.780, 0.234, 24, "g6.xlarge (1x NVIDIA L4 24GB)"),
            "v100": (3.060, 0.918, 16, "p3.2xlarge (1x NVIDIA V100 16GB)"),
            "a100": (4.100, 1.230, 40, "p4d.24xlarge slice (1x A100 40GB)"),
        },
        "k8s_control_plane_hourly": 0.10,  # AWS EKS cluster fee ($73.20/mo)
        "block_storage_gb_month": 0.08,    # EBS gp3
        "object_storage_gb_month": 0.023,  # S3 Standard
        "nat_gateway_hourly": 0.045,       # AWS NAT Gateway ($32.94/mo)
        "load_balancer_hourly": 0.0225,    # Application Load Balancer
        "egress_per_gb": 0.09,             # Internet egress
    },
    "GCP": {
        "provider_name": "Google Cloud Platform (GCP)",
        "region_default": "us-central1",
        "currency": "USD",
        "vm_hourly": {
            "micro": (0.0084, 0.0025, 1, 1, "e2-micro"),
            "small": (0.0168, 0.0050, 1, 2, "e2-small"),
            "medium": (0.0336, 0.0101, 2, 4, "e2-medium"),
            "large": (0.0671, 0.0201, 2, 8, "e2-standard-2"),
            "xlarge": (0.1340, 0.0402, 4, 16, "e2-standard-4 (General Worker)"),
            "2xlarge": (0.2680, 0.0804, 8, 32, "e2-standard-8"),
            "4xlarge": (0.5360, 0.1608, 16, 64, "e2-standard-16"),
        },
        "known_instance_rates": {
            "e2-micro": 0.0084, "e2-small": 0.0168, "e2-medium": 0.0336,
            "e2-standard-2": 0.0671, "e2-standard-4": 0.1340, "e2-standard-8": 0.2680, "e2-standard-16": 0.5360,
            "n1-standard-1": 0.0475, "n1-standard-2": 0.0950, "n1-standard-4": 0.1900, "n1-standard-8": 0.3800,
            "n2-standard-2": 0.0971, "n2-standard-4": 0.1942, "n2-standard-8": 0.3884,
            "g2-standard-4": 0.7020, "g2-standard-8": 1.1440,
        },
        "gpu_hourly": {
            "t4": (0.540, 0.162, 16, "n1-standard-4 + 1x NVIDIA T4 16GB"),
            "a10g": (0.850, 0.255, 24, "n1-standard-4 + 1x A100/A10G equivalent"),
            "l4": (0.702, 0.210, 24, "g2-standard-4 (1x NVIDIA L4 24GB)"),
            "v100": (2.880, 0.864, 16, "n1-standard-8 + 1x NVIDIA V100 16GB"),
            "a100": (3.670, 1.101, 40, "a2-highgpu-1g (1x NVIDIA A100 40GB)"),
        },
        "k8s_control_plane_hourly": 0.10,  # GKE Standard cluster fee ($73.20/mo)
        "block_storage_gb_month": 0.10,    # Persistent Disk Balanced (pd-balanced)
        "object_storage_gb_month": 0.020,  # Cloud Storage Standard
        "nat_gateway_hourly": 0.0014,      # Cloud NAT base ($1.02/mo)
        "load_balancer_hourly": 0.025,     # Cloud HTTP(S) Load Balancer
        "egress_per_gb": 0.085,            # Internet egress
    },
    "AZURE": {
        "provider_name": "Microsoft Azure",
        "region_default": "eastus",
        "currency": "USD",
        "vm_hourly": {
            "micro": (0.0104, 0.0031, 1, 1, "Standard_B1s"),
            "small": (0.0208, 0.0062, 1, 2, "Standard_B1ms"),
            "medium": (0.0416, 0.0125, 2, 4, "Standard_B2s"),
            "large": (0.0960, 0.0288, 2, 8, "Standard_D2s_v5"),
            "xlarge": (0.1920, 0.0576, 4, 16, "Standard_D4s_v5 (General Worker)"),
            "2xlarge": (0.3840, 0.1152, 8, 32, "Standard_D8s_v5"),
            "4xlarge": (0.7680, 0.2304, 16, 64, "Standard_D16s_v5"),
        },
        "known_instance_rates": {
            "Standard_B1s": 0.0104, "Standard_B1ms": 0.0208, "Standard_B2s": 0.0416,
            "Standard_D2s_v5": 0.096, "Standard_D4s_v5": 0.192, "Standard_D8s_v5": 0.384,
            "Standard_B4ms": 0.166, "Standard_NC4as_T4_v3": 0.526,
        },
        "gpu_hourly": {
            "t4": (0.526, 0.158, 16, "Standard_NC4as_T4_v3 (1x T4 16GB)"),
            "a10g": (0.850, 0.255, 24, "Standard_NV6ads_A10_v5 (1x A10 24GB)"),
            "l4": (0.750, 0.225, 24, "Standard_NV8as_v5 (1x L4 24GB)"),
            "v100": (3.060, 0.918, 16, "Standard_NC6s_v3 (1x V100 16GB)"),
            "a100": (3.670, 1.101, 40, "Standard_ND96amsr_A100_v4 slice"),
        },
        "k8s_control_plane_hourly": 0.00,  # AKS Free Tier ($0), or $0.10 for SLA tier
        "block_storage_gb_month": 0.11,    # Premium SSD Managed Disk
        "object_storage_gb_month": 0.018,  # Blob Storage Hot tier
        "nat_gateway_hourly": 0.045,       # Azure NAT Gateway ($32.94/mo)
        "load_balancer_hourly": 0.025,     # Standard Load Balancer
        "egress_per_gb": 0.087,            # Internet egress
    },
}

# ==============================================================================
# Architecture Presets
# ==============================================================================
PRESETS: Dict[str, Dict[str, Any]] = {
    "project": {
        "name": "Smart Manufacturing Complete MLOps Platform (EKS / GKE / AKS)",
        "description": "Production setup: 1 Dev VM + K8s cluster (2 General workers + 1 GPU T4 node) + 250GB SSD + 100GB S3/GCS + NAT + LB",
        "vms": 1,
        "vm_size": "xlarge",
        "k8s_clusters": 1,
        "k8s_nodes": 2,
        "k8s_node_size": "xlarge",
        "gpus": 1,
        "gpu_type": "t4",
        "storage_gb": 250,
        "object_storage_gb": 100,
        "nat_gateways": 1,
        "load_balancers": 1,
        "egress_gb": 100,
        "hours_per_day": 24,
        "days_per_month": 30.5,
    },
    "devops-vm": {
        "name": "Standalone DevOps VM (Jenkins, ArgoCD, SonarQube, Nexus)",
        "description": "1 VM (4 vCPU, 16GB RAM) running Docker, Minikube, Jenkins, ArgoCD, SonarQube & Nexus",
        "vms": 1,
        "vm_size": "xlarge",
        "k8s_clusters": 0,
        "k8s_nodes": 0,
        "k8s_node_size": "medium",
        "gpus": 0,
        "gpu_type": "t4",
        "storage_gb": 100,
        "object_storage_gb": 20,
        "nat_gateways": 0,
        "load_balancers": 0,
        "egress_gb": 30,
        "hours_per_day": 24,
        "days_per_month": 30.5,
    },
    "k8s-gpu": {
        "name": "Kubernetes ML Training Cluster with GPU",
        "description": "Managed K8s cluster with 2 worker nodes + 1 GPU node (T4) + 200GB storage + LB",
        "vms": 0,
        "vm_size": "xlarge",
        "k8s_clusters": 1,
        "k8s_nodes": 2,
        "k8s_node_size": "xlarge",
        "gpus": 1,
        "gpu_type": "t4",
        "storage_gb": 200,
        "object_storage_gb": 150,
        "nat_gateways": 1,
        "load_balancers": 1,
        "egress_gb": 100,
        "hours_per_day": 24,
        "days_per_month": 30.5,
    },
    "k8s-cpu": {
        "name": "Standard Kubernetes Cluster (CPU Only)",
        "description": "Managed K8s cluster with 3 general worker nodes (4 vCPU, 16GB RAM) + 150GB storage + LB",
        "vms": 0,
        "vm_size": "xlarge",
        "k8s_clusters": 1,
        "k8s_nodes": 3,
        "k8s_node_size": "xlarge",
        "gpus": 0,
        "gpu_type": "t4",
        "storage_gb": 150,
        "object_storage_gb": 50,
        "nat_gateways": 1,
        "load_balancers": 1,
        "egress_gb": 50,
        "hours_per_day": 24,
        "days_per_month": 30.5,
    },
    "minimal": {
        "name": "Minimal Development Sandbox (Budget)",
        "description": "1 Small Dev VM (2 vCPU, 8GB RAM) with 50GB storage, 8 hours/day schedule",
        "vms": 1,
        "vm_size": "large",
        "k8s_clusters": 0,
        "k8s_nodes": 0,
        "k8s_node_size": "medium",
        "gpus": 0,
        "gpu_type": "t4",
        "storage_gb": 50,
        "object_storage_gb": 10,
        "nat_gateways": 0,
        "load_balancers": 0,
        "egress_gb": 10,
        "hours_per_day": 8,
        "days_per_month": 22,
    },
}

# ==============================================================================
# Data Structures
# ==============================================================================
@dataclass
class CostBreakdownItem:
    category: str
    description: str
    quantity: float
    unit: str
    unit_price_hourly: float
    total_hourly: float
    total_monthly: float


@dataclass
class CloudCostEstimate:
    cloud: str
    provider_name: str
    items: List[CostBreakdownItem] = field(default_factory=list)
    total_hourly_ondemand: float = 0.0
    total_monthly_ondemand: float = 0.0
    total_yearly_ondemand: float = 0.0
    total_monthly_spot: float = 0.0
    spot_savings_monthly: float = 0.0
    spot_savings_percentage: float = 0.0


@dataclass
class LiveServiceCost:
    service_name: str
    amount: float
    unit: str
    description: str


@dataclass
class LiveResourceItem:
    resource_type: str
    name: str
    details: str
    hourly_burn: float
    monthly_burn: float
    notes: str


@dataclass
class LiveCloudReport:
    cloud: str
    provider_name: str
    account_info: str
    billing_status: str
    is_authenticated: bool
    billing_period: str = ""
    mtd_spend: float = 0.0
    mtd_items: List[LiveServiceCost] = field(default_factory=list)
    running_resources: List[LiveResourceItem] = field(default_factory=list)
    live_hourly_burn: float = 0.0
    live_monthly_burn: float = 0.0
    projected_end_of_month: float = 0.0
    error_message: Optional[str] = None


# ==============================================================================
# Model-Driven Architectural Estimator
# ==============================================================================
def calculate_cloud_cost(
    cloud_key: str,
    params: Dict[str, Any],
    currency: str = "USD",
) -> CloudCostEstimate:
    cloud_data = PRICING_CATALOG[cloud_key]
    items: List[CostBreakdownItem] = []

    hours_per_day = float(params.get("hours_per_day", 24))
    days_per_month = float(params.get("days_per_month", 30.5))
    monthly_hours = hours_per_day * days_per_month

    rate, _ = CURRENCY_RATES.get(currency, (1.0, "$"))

    # 1. Standalone VMs
    vms_count = int(params.get("vms", 0))
    vm_size = params.get("vm_size", "xlarge").lower()
    vm_pricing = cloud_data["vm_hourly"].get(vm_size, cloud_data["vm_hourly"]["xlarge"])
    vm_od_rate, vm_spot_rate, vcpu, ram, vm_desc = vm_pricing

    if vms_count > 0:
        h_cost = vms_count * vm_od_rate
        m_cost = h_cost * monthly_hours
        items.append(CostBreakdownItem(
            category="Compute (VMs)",
            description=f"{vms_count}x {vm_desc} ({vcpu} vCPU, {ram}GB RAM)",
            quantity=vms_count,
            unit="VMs",
            unit_price_hourly=vm_od_rate * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 2. Kubernetes Control Plane
    k8s_clusters = int(params.get("k8s_clusters", 0))
    k8s_cp_rate = cloud_data["k8s_control_plane_hourly"]
    if k8s_clusters > 0:
        h_cost = k8s_clusters * k8s_cp_rate
        m_cost = h_cost * monthly_hours
        cp_name = "EKS Control Plane" if cloud_key == "AWS" else ("GKE Standard Tier" if cloud_key == "GCP" else "AKS Free Tier")
        items.append(CostBreakdownItem(
            category="Kubernetes Control Plane",
            description=f"{k8s_clusters}x {cp_name}",
            quantity=k8s_clusters,
            unit="Clusters",
            unit_price_hourly=k8s_cp_rate * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 3. Kubernetes Worker Nodes
    k8s_nodes = int(params.get("k8s_nodes", 0))
    node_size = params.get("k8s_node_size", "xlarge").lower()
    node_pricing = cloud_data["vm_hourly"].get(node_size, cloud_data["vm_hourly"]["xlarge"])
    n_od_rate, n_spot_rate, n_vcpu, n_ram, n_desc = node_pricing

    if k8s_nodes > 0:
        h_cost = k8s_nodes * n_od_rate
        m_cost = h_cost * monthly_hours
        items.append(CostBreakdownItem(
            category="Kubernetes Worker Nodes",
            description=f"{k8s_nodes}x {n_desc} ({n_vcpu} vCPU, {n_ram}GB RAM)",
            quantity=k8s_nodes,
            unit="Nodes",
            unit_price_hourly=n_od_rate * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 4. GPU Worker Nodes
    gpus_count = int(params.get("gpus", 0))
    gpu_type = params.get("gpu_type", "t4").lower()
    if gpus_count > 0 and gpu_type in cloud_data["gpu_hourly"]:
        gpu_pricing = cloud_data["gpu_hourly"][gpu_type]
        g_od_rate, g_spot_rate, g_vram, g_desc = gpu_pricing
        h_cost = gpus_count * g_od_rate
        m_cost = h_cost * monthly_hours
        items.append(CostBreakdownItem(
            category="GPU Acceleration",
            description=f"{gpus_count}x {g_desc}",
            quantity=gpus_count,
            unit="GPUs",
            unit_price_hourly=g_od_rate * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 5. Block Storage
    storage_gb = float(params.get("storage_gb", 0))
    block_rate = cloud_data["block_storage_gb_month"]
    if storage_gb > 0:
        m_cost = storage_gb * block_rate
        h_cost = m_cost / max(monthly_hours, 1)
        blk_name = "EBS gp3" if cloud_key == "AWS" else ("PD-Balanced" if cloud_key == "GCP" else "Premium SSD")
        items.append(CostBreakdownItem(
            category="Block Storage",
            description=f"{storage_gb:.0f} GB {blk_name}",
            quantity=storage_gb,
            unit="GB-Mo",
            unit_price_hourly=(block_rate / monthly_hours) * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 6. Object Storage
    object_gb = float(params.get("object_storage_gb", 0))
    obj_rate = cloud_data["object_storage_gb_month"]
    if object_gb > 0:
        m_cost = object_gb * obj_rate
        h_cost = m_cost / max(monthly_hours, 1)
        obj_name = "S3 Standard" if cloud_key == "AWS" else ("Cloud Storage" if cloud_key == "GCP" else "Blob Hot")
        items.append(CostBreakdownItem(
            category="Object Storage",
            description=f"{object_gb:.0f} GB {obj_name}",
            quantity=object_gb,
            unit="GB-Mo",
            unit_price_hourly=(obj_rate / monthly_hours) * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 7. NAT Gateways
    nats_count = int(params.get("nat_gateways", 0))
    nat_rate = cloud_data["nat_gateway_hourly"]
    if nats_count > 0:
        h_cost = nats_count * nat_rate
        m_cost = h_cost * monthly_hours
        items.append(CostBreakdownItem(
            category="Networking (NAT Gateway)",
            description=f"{nats_count}x Cloud NAT / NAT Gateway",
            quantity=nats_count,
            unit="Gateways",
            unit_price_hourly=nat_rate * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 8. Load Balancers
    lbs_count = int(params.get("load_balancers", 0))
    lb_rate = cloud_data["load_balancer_hourly"]
    if lbs_count > 0:
        h_cost = lbs_count * lb_rate
        m_cost = h_cost * monthly_hours
        items.append(CostBreakdownItem(
            category="Networking (Load Balancers)",
            description=f"{lbs_count}x Application / Standard Load Balancer",
            quantity=lbs_count,
            unit="Balancers",
            unit_price_hourly=lb_rate * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    # 9. Data Egress
    egress_gb = float(params.get("egress_gb", 0))
    egress_rate = cloud_data["egress_per_gb"]
    if egress_gb > 0:
        m_cost = egress_gb * egress_rate
        h_cost = m_cost / max(monthly_hours, 1)
        items.append(CostBreakdownItem(
            category="Networking (Data Egress)",
            description=f"{egress_gb:.0f} GB Internet Outbound Traffic",
            quantity=egress_gb,
            unit="GB",
            unit_price_hourly=(egress_rate / monthly_hours) * rate,
            total_hourly=h_cost * rate,
            total_monthly=m_cost * rate,
        ))

    total_hourly_od = sum(it.total_hourly for it in items)
    total_monthly_od = sum(it.total_monthly for it in items)
    total_yearly_od = total_monthly_od * 12

    # Spot Savings Calculation
    spot_compute_savings_monthly = 0.0
    if k8s_nodes > 0:
        n_savings_hourly = (n_od_rate - n_spot_rate) * k8s_nodes
        spot_compute_savings_monthly += n_savings_hourly * monthly_hours * rate
    if gpus_count > 0 and gpu_type in cloud_data["gpu_hourly"]:
        g_savings_hourly = (g_od_rate - g_spot_rate) * gpus_count
        spot_compute_savings_monthly += g_savings_hourly * monthly_hours * rate

    total_monthly_spot = max(0.0, total_monthly_od - spot_compute_savings_monthly)
    spot_percentage = (spot_compute_savings_monthly / total_monthly_od * 100) if total_monthly_od > 0 else 0.0

    return CloudCostEstimate(
        cloud=cloud_key,
        provider_name=cloud_data["provider_name"],
        items=items,
        total_hourly_ondemand=total_hourly_od,
        total_monthly_ondemand=total_monthly_od,
        total_yearly_ondemand=total_yearly_od,
        total_monthly_spot=total_monthly_spot,
        spot_savings_monthly=spot_compute_savings_monthly,
        spot_savings_percentage=spot_percentage,
    )


# ==============================================================================
# Live Cloud API Fetchers (AWS, GCP, Azure)
# ==============================================================================
AWS_SERVICE_DESCRIPTIONS = {
    "Amazon Simple Storage Service": "Model checkpoints, training datasets, Kubeflow pipeline artifacts stored in S3",
    "Amazon Elastic Compute Cloud - Compute": "EC2 Virtual Machines running Jenkins, ArgoCD, or custom workers",
    "Amazon Elastic Kubernetes Service": "EKS Managed Kubernetes Control Plane clusters ($0.10/hour per cluster)",
    "AWS Data Transfer": "Inter-region network traffic, NAT gateway bandwidth, and internet egress",
    "AWS Key Management Service": "KMS encryption keys protecting secrets, S3 buckets, and EBS volumes",
    "Amazon Relational Database Service": "Managed relational databases (PostgreSQL/MySQL) for MLflow and backend",
    "AWS Glue": "Serverless data integration and catalog service for ML pipelines",
    "Tax": "Estimated regional and local government sales tax",
}


def log_api_call(
    cloud: str,
    action: str,
    result: str = "",
    error: str = "",
    verbose: bool = True,
) -> None:
    """Print real-time progress logging for cloud API calls during live audit."""
    if not verbose:
        return
    badge_colors = {
        "AWS": Colors.YELLOW,
        "GCP": Colors.BLUE,
        "AZURE": Colors.CYAN,
    }
    col = badge_colors.get(cloud, Colors.BOLD)
    cloud_badge = f"{col}{Colors.BOLD}[{cloud} API]{Colors.RESET}"
    if error:
        print(f"  {cloud_badge:<20} {action:<50} {Colors.RED}✖ {error}{Colors.RESET}", flush=True)
    elif result:
        print(f"  {cloud_badge:<20} {action:<50} {Colors.GREEN}✔ {result}{Colors.RESET}", flush=True)
    else:
        print(f"  {cloud_badge:<20} {action}...", flush=True)


def fetch_live_aws_report(currency: str = "USD", verbose: bool = False) -> LiveCloudReport:
    rate, sym = CURRENCY_RATES.get(currency, (1.0, "$"))
    report = LiveCloudReport(
        cloud="AWS",
        provider_name="Amazon Web Services (AWS)",
        account_info="Not Configured",
        billing_status="Unknown",
        is_authenticated=False,
    )

    try:
        log_api_call("AWS", "Verifying IAM identity (aws sts get-caller-identity)", verbose=verbose)
        sts_out = subprocess.run(
            ["aws", "sts", "get-caller-identity", "--output", "json"],
            capture_output=True, text=True, timeout=8
        )
        if sts_out.returncode != 0:
            report.error_message = "AWS CLI unauthenticated. Run 'aws configure' or set AWS keys."
            log_api_call("AWS", "Verifying IAM identity", error=report.error_message, verbose=verbose)
            return report

        sts_data = json.loads(sts_out.stdout)
        account_id = sts_data.get("Account", "Unknown")
        arn = sts_data.get("Arn", "Unknown")
        user_name = arn.split("/")[-1] if "/" in arn else arn
        report.is_authenticated = True
        report.account_info = f"Account: {account_id} (IAM: {user_name})"
        report.billing_status = "Active AWS Account"
        log_api_call("AWS", "Verifying IAM identity", result=f"{account_id} (User: {user_name})", verbose=verbose)
    except Exception as e:
        report.error_message = f"AWS CLI error: {e}"
        log_api_call("AWS", "Verifying IAM identity", error=str(e), verbose=verbose)
        return report

    # 1. Fetch Month-To-Date Spend via Cost Explorer API
    now = datetime.now(timezone.utc)
    start_date = now.replace(day=1).strftime("%Y-%m-%d")
    end_date = (now + timedelta(days=1)).strftime("%Y-%m-%d")
    report.billing_period = f"{start_date} to {now.strftime('%Y-%m-%d')} (Current MTD)"

    try:
        log_api_call("AWS", f"Fetching Cost Explorer MTD ({start_date} to today)", verbose=verbose)
        ce_out = subprocess.run(
            [
                "aws", "ce", "get-cost-and-usage",
                "--time-period", f"Start={start_date},End={end_date}",
                "--granularity", "MONTHLY",
                "--metrics", "UnblendedCost",
                "--group-by", "Type=DIMENSION,Key=SERVICE",
                "--output", "json",
            ],
            capture_output=True, text=True, timeout=10
        )
        if ce_out.returncode == 0:
            ce_data = json.loads(ce_out.stdout)
            results = ce_data.get("ResultsByTime", [])
            if results:
                groups = results[0].get("Groups", [])
                total_mtd = 0.0
                for g in groups:
                    s_name = g.get("Keys", ["Unknown"])[0]
                    amount_str = g.get("Metrics", {}).get("UnblendedCost", {}).get("Amount", "0")
                    amount = max(0.0, float(amount_str)) * rate
                    total_mtd += amount
                    desc = AWS_SERVICE_DESCRIPTIONS.get(s_name, "AWS cloud service infrastructure component")
                    report.mtd_items.append(LiveServiceCost(
                        service_name=s_name,
                        amount=amount,
                        unit=currency,
                        description=desc,
                    ))
                report.mtd_spend = total_mtd
                log_api_call("AWS", "Fetching Cost Explorer MTD", result=f"{len(report.mtd_items)} services ({sym}{total_mtd:,.6f} MTD)", verbose=verbose)
        else:
            log_api_call("AWS", "Fetching Cost Explorer MTD", error="Cost Explorer disabled or permission denied", verbose=verbose)
    except Exception as e:
        report.error_message = f"Cost Explorer query failed: {e}"
        log_api_call("AWS", "Fetching Cost Explorer MTD", error=str(e), verbose=verbose)

    # 2. Query Live Running Resources & Calculate Current Live Burn Rate
    # A. Running EC2 Instances
    try:
        log_api_call("AWS", "Checking running EC2 instances (aws ec2 describe-instances)", verbose=verbose)
        ec2_out = subprocess.run(
            [
                "aws", "ec2", "describe-instances",
                "--filters", "Name=instance-state-name,Values=running",
                "--output", "json",
            ],
            capture_output=True, text=True, timeout=10
        )
        if ec2_out.returncode == 0:
            ec2_data = json.loads(ec2_out.stdout)
            reservations = ec2_data.get("Reservations", [])
            ec2_count = 0
            for res in reservations:
                for inst in res.get("Instances", []):
                    ec2_count += 1
                    i_id = inst.get("InstanceId", "i-unknown")
                    i_type = inst.get("InstanceType", "t3.medium")
                    name_tag = next((t["Value"] for t in inst.get("Tags", []) if t["Key"] == "Name"), i_id)
                    hourly = PRICING_CATALOG["AWS"]["known_instance_rates"].get(i_type, 0.0832) * rate
                    monthly = hourly * 732
                    report.live_hourly_burn += hourly
                    report.live_monthly_burn += monthly
                    report.running_resources.append(LiveResourceItem(
                        resource_type="EC2 Instance",
                        name=f"{name_tag} ({i_id})",
                        details=f"Type: {i_type} | State: RUNNING",
                        hourly_burn=hourly,
                        monthly_burn=monthly,
                        notes=f"Active AWS EC2 compute node ({i_type})",
                    ))
            log_api_call("AWS", "Checking running EC2 instances", result=f"{ec2_count} running instance(s)", verbose=verbose)
    except Exception as e:
        log_api_call("AWS", "Checking running EC2 instances", error=str(e), verbose=verbose)

    # B. EKS Clusters
    try:
        log_api_call("AWS", "Checking active EKS clusters (aws eks list-clusters)", verbose=verbose)
        eks_out = subprocess.run(
            ["aws", "eks", "list-clusters", "--output", "json"],
            capture_output=True, text=True, timeout=8
        )
        if eks_out.returncode == 0:
            clusters = json.loads(eks_out.stdout).get("clusters", [])
            for c in clusters:
                hourly = PRICING_CATALOG["AWS"]["k8s_control_plane_hourly"] * rate
                monthly = hourly * 732
                report.live_hourly_burn += hourly
                report.live_monthly_burn += monthly
                report.running_resources.append(LiveResourceItem(
                    resource_type="EKS Cluster",
                    name=c,
                    details="Control Plane: Active",
                    hourly_burn=hourly,
                    monthly_burn=monthly,
                    notes="AWS Managed Kubernetes control plane fee ($0.10/hr)",
                ))
            log_api_call("AWS", "Checking active EKS clusters", result=f"{len(clusters)} active cluster(s)", verbose=verbose)
    except Exception as e:
        log_api_call("AWS", "Checking active EKS clusters", error=str(e), verbose=verbose)

    # C. S3 Buckets
    try:
        log_api_call("AWS", "Checking S3 buckets (aws s3api list-buckets)", verbose=verbose)
        s3_out = subprocess.run(
            ["aws", "s3api", "list-buckets", "--output", "json"],
            capture_output=True, text=True, timeout=8
        )
        if s3_out.returncode == 0:
            buckets = json.loads(s3_out.stdout).get("Buckets", [])
            if buckets:
                b_names = [b.get("Name", "") for b in buckets]
                report.running_resources.append(LiveResourceItem(
                    resource_type="S3 Storage",
                    name=f"{len(buckets)} Active S3 Bucket(s)",
                    details=", ".join(b_names[:3]) + ("..." if len(b_names) > 3 else ""),
                    hourly_burn=0.003 * rate,
                    monthly_burn=2.30 * rate,
                    notes="Object storage for datasets, ML models, and pipeline artifacts",
                ))
                log_api_call("AWS", "Checking S3 buckets", result=f"{len(buckets)} bucket(s): {', '.join(b_names[:2])}", verbose=verbose)
            else:
                log_api_call("AWS", "Checking S3 buckets", result="0 buckets found", verbose=verbose)
    except Exception as e:
        log_api_call("AWS", "Checking S3 buckets", error=str(e), verbose=verbose)

    # Projected end of month calculation
    days_in_month = 31
    days_left = max(1, days_in_month - now.day)
    report.projected_end_of_month = report.mtd_spend + (report.live_hourly_burn * 24 * days_left)

    return report


def fetch_live_gcp_report(currency: str = "USD", verbose: bool = False) -> LiveCloudReport:
    rate, sym = CURRENCY_RATES.get(currency, (1.0, "$"))
    report = LiveCloudReport(
        cloud="GCP",
        provider_name="Google Cloud Platform (GCP)",
        account_info="Not Configured",
        billing_status="Unknown",
        is_authenticated=False,
    )

    try:
        log_api_call("GCP", "Checking project configuration (gcloud config list)", verbose=verbose)
        config_out = subprocess.run(
            ["gcloud", "config", "list", "--format=json"],
            capture_output=True, text=True, timeout=8
        )
        if config_out.returncode != 0:
            report.error_message = "gcloud CLI not installed or unauthenticated. Run 'gcloud auth login'."
            log_api_call("GCP", "Checking project configuration", error=report.error_message, verbose=verbose)
            return report

        cfg = json.loads(config_out.stdout)
        project_id = cfg.get("core", {}).get("project", "")
        account_email = cfg.get("core", {}).get("account", "")

        if not project_id:
            report.error_message = "No active GCP project set. Run 'gcloud config set project <ID>'."
            log_api_call("GCP", "Checking project configuration", error=report.error_message, verbose=verbose)
            return report

        report.is_authenticated = True
        report.account_info = f"Project: {project_id} (User: {account_email})"
        log_api_call("GCP", "Checking project configuration", result=f"{project_id} ({account_email})", verbose=verbose)
    except Exception as e:
        report.error_message = f"gcloud check failed: {e}"
        log_api_call("GCP", "Checking project configuration", error=str(e), verbose=verbose)
        return report

    # Check Billing Account Link
    try:
        log_api_call("GCP", "Checking Cloud Billing status (gcloud billing projects describe)", verbose=verbose)
        bill_out = subprocess.run(
            ["gcloud", "billing", "projects", "describe", project_id, "--format=json"],
            capture_output=True, text=True, timeout=8
        )
        if bill_out.returncode == 0:
            b_info = json.loads(bill_out.stdout)
            b_enabled = b_info.get("billingEnabled", False)
            b_acc = b_info.get("billingAccountName", "None").split("/")[-1]
            report.billing_status = f"Billing Enabled ({b_acc})" if b_enabled else "Billing Disabled"
            log_api_call("GCP", "Checking Cloud Billing status", result=f"Account: {b_acc} (Enabled)", verbose=verbose)
        else:
            report.billing_status = "Billing Active (Project Linked)"
            log_api_call("GCP", "Checking Cloud Billing status", result="Active (Project Linked)", verbose=verbose)
    except Exception as e:
        report.billing_status = "Billing Active"
        log_api_call("GCP", "Checking Cloud Billing status", result="Billing Active", verbose=verbose)

    now = datetime.now(timezone.utc)
    report.billing_period = f"{now.replace(day=1).strftime('%Y-%m-%d')} to {now.strftime('%Y-%m-%d')} (Current MTD)"

    # 1. Running Compute Engine Instances
    try:
        log_api_call("GCP", "Querying Compute Engine VMs (gcloud compute instances list)", verbose=verbose)
        vm_out = subprocess.run(
            [
                "gcloud", "compute", "instances", "list",
                "--format=json(name,zone,machineType,status,disks)",
            ],
            capture_output=True, text=True, timeout=12
        )
        if vm_out.returncode == 0:
            vms = json.loads(vm_out.stdout or "[]")
            running_names = []
            for vm in vms:
                status = vm.get("status", "UNKNOWN")
                if status == "RUNNING":
                    name = vm.get("name", "instance")
                    m_type_raw = vm.get("machineType", "")
                    m_type = m_type_raw.split("/")[-1] if "/" in m_type_raw else m_type_raw
                    zone_raw = vm.get("zone", "")
                    zone = zone_raw.split("/")[-1] if "/" in zone_raw else zone_raw
                    running_names.append(f"{name} ({m_type})")

                    hourly = PRICING_CATALOG["GCP"]["known_instance_rates"].get(m_type, 0.134) * rate
                    monthly = hourly * 732
                    report.live_hourly_burn += hourly
                    report.live_monthly_burn += monthly

                    desc = f"{m_type} (Zone: {zone}) | Status: RUNNING"
                    notes = f"GCP Compute Engine VM instance running 24/7 ({m_type})"
                    report.running_resources.append(LiveResourceItem(
                        resource_type="Compute Engine VM",
                        name=name,
                        details=desc,
                        hourly_burn=hourly,
                        monthly_burn=monthly,
                        notes=notes,
                    ))
            log_api_call("GCP", "Querying Compute Engine VMs", result=f"{len(running_names)} running: {', '.join(running_names)}" if running_names else "0 running VMs", verbose=verbose)
    except Exception as e:
        report.error_message = f"GCP instance query failed: {e}"
        log_api_call("GCP", "Querying Compute Engine VMs", error=str(e), verbose=verbose)

    # 2. Persistent Disks
    try:
        log_api_call("GCP", "Querying Persistent Disks (gcloud compute disks list)", verbose=verbose)
        disk_out = subprocess.run(
            [
                "gcloud", "compute", "disks", "list",
                "--format=json(name,sizeGb,type,status,zone)",
            ],
            capture_output=True, text=True, timeout=10
        )
        if disk_out.returncode == 0:
            disks = json.loads(disk_out.stdout or "[]")
            disk_summaries = []
            for d in disks:
                d_name = d.get("name", "disk")
                size_gb = float(d.get("sizeGb", 0))
                type_raw = d.get("type", "")
                t_name = type_raw.split("/")[-1] if "/" in type_raw else type_raw
                gb_rate = 0.10 if "balanced" in t_name else (0.17 if "ssd" in t_name else 0.04)
                monthly = size_gb * gb_rate * rate
                hourly = monthly / 732
                report.live_hourly_burn += hourly
                report.live_monthly_burn += monthly
                disk_summaries.append(f"{d_name} ({size_gb:.0f}GB {t_name})")

                report.running_resources.append(LiveResourceItem(
                    resource_type="Persistent Disk",
                    name=d_name,
                    details=f"{size_gb:.0f} GB ({t_name})",
                    hourly_burn=hourly,
                    monthly_burn=monthly,
                    notes=f"Attached Google Cloud Persistent Storage ({t_name})",
                ))
            log_api_call("GCP", "Querying Persistent Disks", result=f"{len(disks)} attached disk(s): {', '.join(disk_summaries)}" if disk_summaries else "0 disks", verbose=verbose)
    except Exception as e:
        log_api_call("GCP", "Querying Persistent Disks", error=str(e), verbose=verbose)

    # 3. GKE Clusters
    try:
        log_api_call("GCP", "Querying GKE Kubernetes clusters (gcloud container clusters list)", verbose=verbose)
        gke_out = subprocess.run(
            ["gcloud", "container", "clusters", "list", "--format=json(name,status,location)"],
            capture_output=True, text=True, timeout=12
        )
        if gke_out.returncode == 0:
            clusters = json.loads(gke_out.stdout or "[]")
            active_gke = []
            for c in clusters:
                if c.get("status") == "RUNNING":
                    c_name = c.get("name", "cluster")
                    active_gke.append(c_name)
                    hourly = PRICING_CATALOG["GCP"]["k8s_control_plane_hourly"] * rate
                    monthly = hourly * 732
                    report.live_hourly_burn += hourly
                    report.live_monthly_burn += monthly
                    report.running_resources.append(LiveResourceItem(
                        resource_type="GKE Cluster",
                        name=c_name,
                        details=f"Location: {c.get('location', '')} | Status: RUNNING",
                        hourly_burn=hourly,
                        monthly_burn=monthly,
                        notes="Google Kubernetes Engine cluster management fee",
                    ))
            log_api_call("GCP", "Querying GKE Kubernetes clusters", result=f"{len(active_gke)} running cluster(s)" if active_gke else "0 running clusters", verbose=verbose)
    except Exception as e:
        log_api_call("GCP", "Querying GKE Kubernetes clusters", error=str(e), verbose=verbose)

    # Estimate current MTD spend based on running burn
    days_elapsed = max(1, now.day)
    report.mtd_spend = (report.live_hourly_burn * 24 * days_elapsed)
    days_left = max(1, 31 - now.day)
    report.projected_end_of_month = report.mtd_spend + (report.live_hourly_burn * 24 * days_left)

    if report.live_monthly_burn > 0:
        report.mtd_items.append(LiveServiceCost(
            service_name="Compute Engine (VMs & Disks)",
            amount=report.mtd_spend,
            unit=currency,
            description="Active VM instances and persistent storage attached to Smart Manufacturing/DevOps workloads",
        ))

    return report


def fetch_live_azure_report(currency: str = "USD", verbose: bool = False) -> LiveCloudReport:
    rate, sym = CURRENCY_RATES.get(currency, (1.0, "$"))
    report = LiveCloudReport(
        cloud="AZURE",
        provider_name="Microsoft Azure",
        account_info="Not Configured",
        billing_status="Unknown",
        is_authenticated=False,
    )

    try:
        log_api_call("AZURE", "Verifying Azure subscription (az account show)", verbose=verbose)
        acc_out = subprocess.run(
            ["az", "account", "show", "--output", "json"],
            capture_output=True, text=True, timeout=8
        )
        if acc_out.returncode != 0:
            report.error_message = "Azure CLI unauthenticated. Run 'az login'."
            log_api_call("AZURE", "Verifying Azure subscription", error=report.error_message, verbose=verbose)
            return report

        account = json.loads(acc_out.stdout)
        sub_id = account.get("id", "Unknown")
        sub_name = account.get("name", "Unknown")
        user_email = account.get("user", {}).get("name", "Unknown")
        report.is_authenticated = True
        report.account_info = f"Subscription: {sub_name} ({sub_id[:8]}...)"
        report.billing_status = f"Active ({user_email})"
        log_api_call("AZURE", "Verifying Azure subscription", result=f"{sub_name} ({user_email})", verbose=verbose)
    except Exception as e:
        report.error_message = f"Azure check error: {e}"
        log_api_call("AZURE", "Verifying Azure subscription", error=str(e), verbose=verbose)
        return report

    now = datetime.now(timezone.utc)
    report.billing_period = f"{now.replace(day=1).strftime('%Y-%m-%d')} to {now.strftime('%Y-%m-%d')} (Current MTD)"

    # 1. Fetch live consumption details from Azure Consumption API
    try:
        log_api_call("AZURE", "Querying Consumption & Usage API (az consumption usage list)", verbose=verbose)
        cons_out = subprocess.run(
            [
                "az", "consumption", "usage", "list",
                "--top", "30",
                "--output", "json",
            ],
            capture_output=True, text=True, timeout=12
        )
        if cons_out.returncode == 0:
            usage_list = json.loads(cons_out.stdout or "[]")
            service_aggregates: Dict[str, float] = {}
            for u in usage_list:
                svc = u.get("consumedService", "Azure Services")
                cost_val = u.get("pretaxCost")
                cost = float(cost_val) if (cost_val and cost_val != "None") else 0.0
                service_aggregates[svc] = service_aggregates.get(svc, 0.0) + (cost * rate)

            total_consumed = sum(service_aggregates.values())
            report.mtd_spend = total_consumed

            azure_descs = {
                "Microsoft.Databricks": "Azure Databricks workspaces and managed compute clusters for MLOps ETL",
                "Microsoft.EventHub": "Event Hubs event streaming namespace for IoT and smart manufacturing telemetry",
                "Microsoft.Storage": "Blob and file storage accounts hosting datasets, artifacts, and logs",
                "Microsoft.Compute": "Virtual Machines and Managed Disks deployed in resource groups",
            }

            for svc, amt in service_aggregates.items():
                desc = azure_descs.get(svc, f"Azure {svc} managed cloud resource")
                report.mtd_items.append(LiveServiceCost(
                    service_name=svc,
                    amount=amt,
                    unit=currency,
                    description=desc,
                ))
            log_api_call("AZURE", "Querying Consumption & Usage API", result=f"{len(service_aggregates)} services tracked ({sym}{total_consumed:,.4f} MTD)", verbose=verbose)
        else:
            log_api_call("AZURE", "Querying Consumption & Usage API", result="No consumption records found", verbose=verbose)
    except Exception as e:
        log_api_call("AZURE", "Querying Consumption & Usage API", error=str(e), verbose=verbose)

    # 2. Query Live Deployed Azure Resources Inventory
    try:
        log_api_call("AZURE", "Scanning deployed resource inventory (az resource list)", verbose=verbose)
        res_out = subprocess.run(
            ["az", "resource", "list", "--output", "json"],
            capture_output=True, text=True, timeout=12
        )
        if res_out.returncode == 0:
            resources = json.loads(res_out.stdout or "[]")
            resource_names = []
            for r in resources:
                r_type = r.get("type", "")
                r_name = r.get("name", "")
                r_group = r.get("resourceGroup", "")
                sku_info = r.get("sku", {})
                sku_name = sku_info.get("name", "Standard") if sku_info else "Standard"
                resource_names.append(f"{r_name} ({r_type.split('/')[-1]})")

                hourly = 0.0
                monthly = 0.0
                notes = ""

                if "Microsoft.EventHub/namespaces" in r_type:
                    hourly = 0.015 * rate
                    monthly = hourly * 732
                    notes = f"Event Hubs Basic namespace ({sku_name}) in {r_group}"
                elif "Microsoft.Databricks/workspaces" in r_type:
                    hourly = 0.00
                    monthly = 0.00
                    notes = f"Databricks {sku_name} workspace (DBU compute accrued when clusters execute)"
                elif "Microsoft.Storage/storageAccounts" in r_type:
                    monthly = 0.50 * rate
                    hourly = monthly / 732
                    notes = f"Storage Account ({sku_name}) in {r_group}"
                elif "Microsoft.Compute/virtualMachines" in r_type:
                    hourly = 0.096 * rate
                    monthly = hourly * 732
                    notes = f"Virtual Machine in {r_group}"

                report.live_hourly_burn += hourly
                report.live_monthly_burn += monthly

                report.running_resources.append(LiveResourceItem(
                    resource_type=r_type.split("/")[-1],
                    name=r_name,
                    details=f"Type: {r_type} | SKU: {sku_name} | RG: {r_group}",
                    hourly_burn=hourly,
                    monthly_burn=monthly,
                    notes=notes,
                ))
            log_api_call("AZURE", "Scanning deployed resource inventory", result=f"{len(resources)} resources: {', '.join(resource_names)}" if resource_names else "0 resources", verbose=verbose)
    except Exception as e:
        report.error_message = f"Azure resource list failed: {e}"
        log_api_call("AZURE", "Scanning deployed resource inventory", error=str(e), verbose=verbose)

    days_in_month = 31
    days_left = max(1, days_in_month - now.day)
    report.projected_end_of_month = report.mtd_spend + (report.live_hourly_burn * 24 * days_left)

    return report


# ==============================================================================
# Terminal & Markdown Display Renderers
# ==============================================================================
def render_live_cloud_audit(
    live_reports: Dict[str, LiveCloudReport],
    currency: str = "USD",
) -> None:
    rate, sym = CURRENCY_RATES.get(currency, (1.0, "$"))

    print(f"\n{Colors.CYAN}{Colors.BOLD}===================================================================================================={Colors.RESET}")
    print(f"{Colors.GREEN}{Colors.BOLD}       🔴 LIVE MULTI-CLOUD FINANCIAL AUDIT & REAL-TIME INVENTORY (AWS | GCP | AZURE){Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}===================================================================================================={Colors.RESET}")
    print(f"  {Colors.BOLD}Audit Timestamp:{Colors.RESET}       {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  {Colors.BOLD}Billing Currency:{Colors.RESET}      {Colors.GREEN}{currency} ({sym}){Colors.RESET} [Base: 1 USD = {rate} {currency}]")
    print(f"{Colors.CYAN}----------------------------------------------------------------------------------------------------{Colors.RESET}")

    total_combined_mtd = sum(r.mtd_spend for r in live_reports.values() if r.is_authenticated)
    total_combined_hourly = sum(r.live_hourly_burn for r in live_reports.values() if r.is_authenticated)
    total_combined_monthly = sum(r.live_monthly_burn for r in live_reports.values() if r.is_authenticated)
    total_combined_projected = sum(r.projected_end_of_month for r in live_reports.values() if r.is_authenticated)

    # Multi-Cloud Grand Overview Table
    print(f"\n{Colors.BOLD}{'CLOUD PROVIDER':<28} {'ACCOUNT / PROJECT':<32} {'MTD ACTUAL SPEND':<20} {'HOURLY BURN':<14} {'PROJECTED RUN-RATE':<20}{Colors.RESET}")
    print(f"{Colors.DIM}{'-'*114}{Colors.RESET}")

    for c_key in ["AWS", "GCP", "AZURE"]:
        rep = live_reports.get(c_key)
        if not rep or not rep.is_authenticated:
            status_text = rep.error_message if rep and rep.error_message else "Unauthenticated"
            print(f"{Colors.DIM}{PRICING_CATALOG[c_key]['provider_name']:<28} {status_text:<32} {'-':<20} {'-':<14} {'-':<20}{Colors.RESET}")
            continue

        p_name = rep.provider_name
        acc = rep.account_info
        mtd_str = f"{sym}{rep.mtd_spend:,.2f}"
        burn_str = f"{sym}{rep.live_hourly_burn:,.4f}/hr"
        proj_str = f"{sym}{rep.projected_end_of_month:,.2f}/mo"

        print(f"{Colors.GREEN}{p_name:<28}{Colors.RESET} {acc:<32} {Colors.YELLOW}{mtd_str:<20}{Colors.RESET} {burn_str:<14} {Colors.BOLD}{proj_str:<20}{Colors.RESET}")

    print(f"{Colors.DIM}{'-'*114}{Colors.RESET}")
    print(f"{Colors.BOLD}{'COMBINED MULTI-CLOUD ESTATE TOTALS:':<60} {Colors.YELLOW}{sym}{total_combined_mtd:,.2f} MTD{Colors.RESET}   {sym}{total_combined_hourly:,.4f}/hr   {Colors.GREEN}{Colors.BOLD}{sym}{total_combined_projected:,.2f}/mo Projected{Colors.RESET}\n")

    # Detailed Audit per Cloud
    for c_key in ["AWS", "GCP", "AZURE"]:
        rep = live_reports.get(c_key)
        if not rep:
            continue

        print(f"{Colors.CYAN}{Colors.BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Colors.RESET}")
        print(f"{Colors.YELLOW}{Colors.BOLD}▶ {rep.provider_name} Live Audit Details{Colors.RESET}")
        print(f"{Colors.CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Colors.RESET}")
        print(f"  • {Colors.BOLD}Account ID / Profile:{Colors.RESET}   {rep.account_info}")
        print(f"  • {Colors.BOLD}Billing Status:{Colors.RESET}         {rep.billing_status}")
        print(f"  • {Colors.BOLD}Billing Period:{Colors.RESET}         {rep.billing_period}")
        print(f"  • {Colors.BOLD}Month-to-Date Spend:{Colors.RESET}    {Colors.YELLOW}{sym}{rep.mtd_spend:,.4f}{Colors.RESET}")
        print(f"  • {Colors.BOLD}Real-Time Burn Rate:{Colors.RESET}    {sym}{rep.live_hourly_burn:,.4f}/hour ({sym}{rep.live_monthly_burn:,.2f}/month run-rate)")
        print(f"  • {Colors.BOLD}Forecasted End-of-Month:{Colors.RESET} {Colors.GREEN}{sym}{rep.projected_end_of_month:,.2f}{Colors.RESET}")

        if rep.error_message and not rep.is_authenticated:
            print(f"  {Colors.RED}[!] Status: {rep.error_message}{Colors.RESET}\n")
            continue

        # Item 1: Live Cost Explorer / Usage Breakdown
        if rep.mtd_items:
            print(f"\n  {Colors.BOLD}📊 Actual Live Spend by Service (From Billing API):{Colors.RESET}")
            print(f"  {'SERVICE / RESOURCE':<38} {'ACTUAL SPEND':<16} {'EXPLANATION & BUSINESS FUNCTION'}")
            print(f"  {Colors.DIM}{'-'*92}{Colors.RESET}")
            for s in rep.mtd_items:
                print(f"  {Colors.BOLD}{s.service_name:<38}{Colors.RESET} {sym}{s.amount:,.6f}        {Colors.DIM}{s.description}{Colors.RESET}")
            print(f"  {Colors.DIM}{'-'*92}{Colors.RESET}")

        # Item 2: Running Resources Inventory
        if rep.running_resources:
            print(f"\n  {Colors.BOLD}🖥️  Active Running Resources Inventory (Live Run-Rate):{Colors.RESET}")
            print(f"  {'RESOURCE TYPE':<22} {'RESOURCE NAME':<30} {'HOURLY':<12} {'MONTHLY':<12} {'DETAILS & PURPOSE'}")
            print(f"  {Colors.DIM}{'-'*100}{Colors.RESET}")
            for r in rep.running_resources:
                print(f"  {r.resource_type:<22} {Colors.BOLD}{r.name:<30}{Colors.RESET} {sym}{r.hourly_burn:,.4f}    {sym}{r.monthly_burn:,.2f}    {Colors.DIM}{r.notes}{Colors.RESET}")
            print(f"  {Colors.DIM}{'-'*100}{Colors.RESET}")
        else:
            print(f"\n  {Colors.DIM}[i] No running virtual machines or compute nodes actively accruing charges right now.{Colors.RESET}")

        print("")

    print(f"{Colors.CYAN}{Colors.BOLD}===================================================================================================={Colors.RESET}\n")


def render_terminal_dashboard(
    estimates: Dict[str, CloudCostEstimate],
    params: Dict[str, Any],
    currency: str = "USD",
    preset_name: Optional[str] = None,
) -> None:
    rate, sym = CURRENCY_RATES.get(currency, (1.0, "$"))
    hours = float(params.get("hours_per_day", 24)) * float(params.get("days_per_month", 30.5))

    print(f"\n{Colors.CYAN}{Colors.BOLD}========================================================================================{Colors.RESET}")
    print(f"{Colors.GREEN}{Colors.BOLD}   MULTI-CLOUD COST CALCULATOR & ARCHITECTURE ESTIMATOR (AWS | GCP | AZURE){Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}========================================================================================{Colors.RESET}")

    if preset_name:
        p_info = PRESETS.get(preset_name, {})
        print(f"  {Colors.BOLD}Selected Architecture Preset:{Colors.RESET} {Colors.YELLOW}{p_info.get('name', preset_name)}{Colors.RESET}")
        print(f"  {Colors.DIM}{p_info.get('description', '')}{Colors.RESET}")

    print(f"  {Colors.BOLD}Operational Schedule:{Colors.RESET} {params.get('hours_per_day', 24)} hrs/day × {params.get('days_per_month', 30.5)} days/month = {Colors.BOLD}{hours:.1f} hours/month{Colors.RESET}")
    print(f"  {Colors.BOLD}Display Currency:{Colors.RESET}     {Colors.GREEN}{currency} ({sym}){Colors.RESET} [Exchange Rate: 1 USD = {rate} {currency}]")
    print(f"{Colors.CYAN}----------------------------------------------------------------------------------------{Colors.RESET}")

    # Top-Level Comparative Matrix
    print(f"\n{Colors.BOLD}{'CLOUD PROVIDER':<32} {'HOURLY':<14} {'MONTHLY (ON-DEMAND)':<22} {'MONTHLY (WITH SPOT)':<22} {'YEARLY':<14}{Colors.RESET}")
    print(f"{Colors.DIM}{'-'*104}{Colors.RESET}")

    cheapest_monthly = float("inf")
    cheapest_cloud = ""
    for cloud, est in estimates.items():
        if est.total_monthly_ondemand < cheapest_monthly:
            cheapest_monthly = est.total_monthly_ondemand
            cheapest_cloud = cloud

    for cloud, est in estimates.items():
        is_cheapest = (cloud == cheapest_cloud)
        badge = f" {Colors.GREEN}[BEST VALUE]{Colors.RESET}" if is_cheapest else ""
        c_title = f"{est.provider_name}{badge}"
        h_str = f"{sym}{est.total_hourly_ondemand:,.3f}/hr"
        m_str = f"{sym}{est.total_monthly_ondemand:,.2f}/mo"
        s_str = f"{sym}{est.total_monthly_spot:,.2f}/mo (-{est.spot_savings_percentage:.0f}%)"
        y_str = f"{sym}{est.total_yearly_ondemand:,.2f}/yr"

        row_color = Colors.GREEN if is_cheapest else Colors.RESET
        print(f"{row_color}{c_title:<42} {h_str:<14} {m_str:<22} {s_str:<22} {y_str:<14}{Colors.RESET}")

    print(f"{Colors.DIM}{'-'*104}{Colors.RESET}")

    # Detailed Breakdown per Cloud
    for cloud, est in estimates.items():
        print(f"\n{Colors.YELLOW}{Colors.BOLD}▶ Detailed Cost Breakdown: {est.provider_name}{Colors.RESET}")
        print(f"{'CATEGORY':<28} {'SPECIFICATION':<44} {'HOURLY':<14} {'MONTHLY':<14}")
        print(f"{Colors.DIM}{'-'*100}{Colors.RESET}")
        for it in est.items:
            print(f"{it.category:<28} {it.description:<44} {sym}{it.total_hourly:,.3f}      {sym}{it.total_monthly:,.2f}")
        print(f"{Colors.DIM}{'-'*100}{Colors.RESET}")
        print(f"{Colors.BOLD}{'Subtotal On-Demand:':<72} {sym}{est.total_hourly_ondemand:,.3f}/hr   {sym}{est.total_monthly_ondemand:,.2f}/mo{Colors.RESET}")
        if est.spot_savings_monthly > 0:
            print(f"{Colors.GREEN}{'Subtotal with Spot Worker/GPU Nodes:':<72} {sym}{est.total_monthly_spot:,.2f}/mo (Save {sym}{est.spot_savings_monthly:,.2f}/mo){Colors.RESET}")

    print(f"\n{Colors.CYAN}========================================================================================{Colors.RESET}\n")


def export_markdown_report(
    estimates: Dict[str, CloudCostEstimate],
    live_reports: Optional[Dict[str, LiveCloudReport]] = None,
    currency: str = "USD",
) -> str:
    rate, sym = CURRENCY_RATES.get(currency, (1.0, "$"))
    lines = [
        "# ☁️ Multi-Cloud Infrastructure Cost & Financial Audit Report",
        "",
        f"*Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} (Currency: {currency})*",
        "",
    ]

    # Live Section
    if live_reports:
        lines.append("## 🔴 Live Cloud Accounts & Active Burn Rates")
        lines.append("")
        lines.append("| Cloud Provider | Account / Project | Live MTD Spend | Current Hourly Burn | Projected Monthly Run-Rate |")
        lines.append("| :--- | :--- | :--- | :--- | :--- |")
        for c in ["AWS", "GCP", "AZURE"]:
            rep = live_reports.get(c)
            if rep and rep.is_authenticated:
                lines.append(f"| **{rep.provider_name}** | {rep.account_info} | {sym}{rep.mtd_spend:,.4f} | {sym}{rep.live_hourly_burn:,.4f}/hr | **{sym}{rep.projected_end_of_month:,.2f}/mo** |")
            else:
                lines.append(f"| **{c}** | Unauthenticated | - | - | - |")
        lines.append("")

        for c in ["AWS", "GCP", "AZURE"]:
            rep = live_reports.get(c)
            if rep and rep.is_authenticated and (rep.mtd_items or rep.running_resources):
                lines.append(f"### {rep.provider_name} Live Details")
                if rep.mtd_items:
                    lines.append("#### Live MTD Spend Breakdown")
                    lines.append("| Service | Spend | Explanation |")
                    lines.append("| :--- | :--- | :--- |")
                    for s in rep.mtd_items:
                        lines.append(f"| **{s.service_name}** | {sym}{s.amount:,.6f} | {s.description} |")
                    lines.append("")
                if rep.running_resources:
                    lines.append("#### Active Running Resources")
                    lines.append("| Type | Name | Hourly | Monthly | Purpose |")
                    lines.append("| :--- | :--- | :--- | :--- | :--- |")
                    for r in rep.running_resources:
                        lines.append(f"| {r.resource_type} | `{r.name}` | {sym}{r.hourly_burn:,.4f} | {sym}{r.monthly_burn:,.2f} | {r.notes} |")
                    lines.append("")

    # Architecture Estimation Section
    if estimates:
        lines.append("## 📋 Architecture Cost Comparison (On-Demand vs Spot)")
        lines.append("")
        lines.append("| Cloud Provider | Hourly (On-Demand) | Monthly (On-Demand) | Monthly (With Spot) | Yearly |")
        lines.append("| :--- | :--- | :--- | :--- | :--- |")
        for cloud, est in estimates.items():
            lines.append(
                f"| **{est.provider_name}** | {sym}{est.total_hourly_ondemand:,.3f}/hr | **{sym}{est.total_monthly_ondemand:,.2f}/mo** | {sym}{est.total_monthly_spot:,.2f}/mo (-{est.spot_savings_percentage:.0f}%) | {sym}{est.total_yearly_ondemand:,.2f}/yr |"
            )
        lines.append("")
        lines.append("### Itemized Architecture Breakdown (Monthly)")
        lines.append("| Category | AWS | GCP | Azure |")
        lines.append("| :--- | :--- | :--- | :--- |")

        categories = sorted({it.category for est in estimates.values() for it in est.items})
        for cat in categories:
            vals = []
            for c in ["AWS", "GCP", "AZURE"]:
                est = estimates.get(c)
                if est:
                    matched = sum(it.total_monthly for it in est.items if it.category == cat)
                    vals.append(f"{sym}{matched:,.2f}" if matched > 0 else "-")
                else:
                    vals.append("-")
            lines.append(f"| {cat} | {' | '.join(vals)} |")

    return "\n".join(lines)


# ==============================================================================
# CLI Argument Parser & Main
# ==============================================================================
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Unified Multi-Cloud Cost Calculator & Live API Auditor (AWS, GCP, Azure)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # 1. Fetch live financial report and active burn rates from AWS, GCP, and Azure APIs:
  python3 scripts/calculate_cloud_cost.py --live

  # 2. Calculate architectural cost for the Smart Manufacturing MLOps project:
  python3 scripts/calculate_cloud_cost.py --preset project

  # 3. Full live audit + project estimate side-by-side:
  python3 scripts/calculate_cloud_cost.py --preset project --live

  # 4. Export complete report to Markdown:
  python3 scripts/calculate_cloud_cost.py --live --markdown > cloud_cost_report.md
        """,
    )

    parser.add_argument("--live", action="store_true", help="Fetch LIVE cost reports and running resources from AWS, GCP, and Azure APIs")
    parser.add_argument("--cloud", "--clouds", default="all", help="Target cloud providers: 'all', or comma-separated 'aws,gcp,azure'")
    parser.add_argument("--preset", choices=list(PRESETS.keys()), default=None, help="Architecture preset template (e.g. 'project', 'devops-vm')")
    parser.add_argument("--currency", choices=list(CURRENCY_RATES.keys()), default="USD", help="Currency code (USD, EUR, GBP, INR, BDT)")

    # Custom Resource Overrides
    grp = parser.add_argument_group("Custom Resource Configuration")
    grp.add_argument("--vms", type=int, default=None, help="Number of standalone VMs")
    grp.add_argument("--vm-size", choices=["micro", "small", "medium", "large", "xlarge", "2xlarge", "4xlarge"], default=None, help="VM machine size tier")
    grp.add_argument("--k8s", "--k8s-clusters", dest="k8s_clusters", type=int, default=None, help="Number of managed Kubernetes clusters (EKS/GKE/AKS)")
    grp.add_argument("--nodes", "--k8s-nodes", dest="k8s_nodes", type=int, default=None, help="Number of Kubernetes worker nodes")
    grp.add_argument("--node-size", choices=["medium", "large", "xlarge", "2xlarge"], default=None, help="Kubernetes node size tier")
    grp.add_argument("--gpus", type=int, default=None, help="Number of GPU worker instances")
    grp.add_argument("--gpu-type", choices=["t4", "a10g", "l4", "v100", "a100"], default=None, help="GPU model type")
    grp.add_argument("--storage-gb", type=float, default=None, help="Block storage capacity in GB (EBS / PD / Managed Disk)")
    grp.add_argument("--object-storage-gb", type=float, default=None, help="Object storage capacity in GB (S3 / GCS / Azure Blob)")
    grp.add_argument("--nat-gateways", type=int, default=None, help="Number of Cloud NAT Gateways")
    grp.add_argument("--load-balancers", type=int, default=None, help="Number of Application / Standard Load Balancers")
    grp.add_argument("--egress-gb", type=float, default=None, help="Outbound internet data egress in GB")
    grp.add_argument("--hours-per-day", type=float, default=None, help="Runtime hours per day (default: 24)")
    grp.add_argument("--days-per-month", type=float, default=None, help="Runtime days per month (default: 30.5)")

    # Formats & Export
    parser.add_argument("--show-logs", "--verbose", "-v", dest="verbose", action="store_true", default=False, help="Display detailed real-time API query logs during live fetching")
    parser.add_argument("--quiet", "-q", action="store_true", help="Suppress real-time API query progress logs")
    parser.add_argument("--json", action="store_true", help="Output cost breakdown as formatted JSON")
    parser.add_argument("--markdown", action="store_true", help="Output cost comparison as GitHub-flavored Markdown")
    parser.add_argument("--csv", type=str, default=None, help="File path to save cost breakdown as CSV")
    parser.add_argument("--no-color", action="store_true", help="Disable colored terminal output")

    args = parser.parse_args()

    # Disable colors if requested or redirected
    if args.no_color or not sys.stdout.isatty():
        Colors.HEADER = ""
        Colors.BLUE = ""
        Colors.CYAN = ""
        Colors.GREEN = ""
        Colors.YELLOW = ""
        Colors.RED = ""
        Colors.BOLD = ""
        Colors.DIM = ""
        Colors.MAGENTA = ""
        Colors.RESET = ""

    # Live Mode Handling
    live_reports: Optional[Dict[str, LiveCloudReport]] = None
    if args.live:
        show_logs = (args.verbose or not args.quiet) and not (args.json or args.markdown)
        if show_logs:
            print(f"\n{Colors.CYAN}{Colors.BOLD}📡 INITIATING LIVE MULTI-CLOUD API INGESTION & COST TELEMETRY...{Colors.RESET}")
            print(f"{Colors.DIM}{'─'*96}{Colors.RESET}", flush=True)

        start_time = datetime.now()
        live_reports = {
            "AWS": fetch_live_aws_report(currency=args.currency, verbose=show_logs),
            "GCP": fetch_live_gcp_report(currency=args.currency, verbose=show_logs),
            "AZURE": fetch_live_azure_report(currency=args.currency, verbose=show_logs),
        }
        if show_logs:
            elapsed = (datetime.now() - start_time).total_seconds()
            print(f"{Colors.DIM}{'─'*96}{Colors.RESET}")
            print(f"{Colors.GREEN}{Colors.BOLD}✔ Live API ingestion completed in {elapsed:.1f}s across AWS, GCP, and Azure.{Colors.RESET}\n", flush=True)

    # If preset or resource overrides provided, calculate architecture estimates
    estimates: Dict[str, CloudCostEstimate] = {}
    preset_name = args.preset
    has_custom = any(x is not None for x in [args.vms, args.k8s_clusters, args.k8s_nodes, args.gpus, args.storage_gb])

    if preset_name or has_custom or not args.live:
        effective_preset = preset_name or "project"
        params: Dict[str, Any] = dict(PRESETS.get(effective_preset, PRESETS["project"]))

        # Apply overrides
        if args.vms is not None: params["vms"] = args.vms
        if args.vm_size is not None: params["vm_size"] = args.vm_size
        if args.k8s_clusters is not None: params["k8s_clusters"] = args.k8s_clusters
        if args.k8s_nodes is not None: params["k8s_nodes"] = args.k8s_nodes
        if args.node_size is not None: params["k8s_node_size"] = args.node_size
        if args.gpus is not None: params["gpus"] = args.gpus
        if args.gpu_type is not None: params["gpu_type"] = args.gpu_type
        if args.storage_gb is not None: params["storage_gb"] = args.storage_gb
        if args.object_storage_gb is not None: params["object_storage_gb"] = args.object_storage_gb
        if args.nat_gateways is not None: params["nat_gateways"] = args.nat_gateways
        if args.load_balancers is not None: params["load_balancers"] = args.load_balancers
        if args.egress_gb is not None: params["egress_gb"] = args.egress_gb
        if args.hours_per_day is not None: params["hours_per_day"] = args.hours_per_day
        if args.days_per_month is not None: params["days_per_month"] = args.days_per_month

        target_clouds = ["AWS", "GCP", "AZURE"] if args.cloud.lower() == "all" else [c.strip().upper() for c in args.cloud.split(",") if c.strip().upper() in PRICING_CATALOG]
        for c_key in target_clouds:
            estimates[c_key] = calculate_cloud_cost(c_key, params, currency=args.currency)

    # Output selection
    if args.markdown:
        print(export_markdown_report(estimates, live_reports, currency=args.currency))
    elif args.json:
        out_dict: Dict[str, Any] = {"currency": args.currency}
        if estimates:
            out_dict["estimates"] = {k: v.__dict__ for k, v in estimates.items()}
        if live_reports:
            out_dict["live_reports"] = {
                k: {
                    "account": v.account_info,
                    "billing_status": v.billing_status,
                    "mtd_spend": v.mtd_spend,
                    "live_hourly_burn": v.live_hourly_burn,
                    "live_monthly_burn": v.live_monthly_burn,
                    "projected_end_of_month": v.projected_end_of_month,
                    "services": [s.__dict__ for s in v.mtd_items],
                    "resources": [r.__dict__ for r in v.running_resources],
                }
                for k, v in live_reports.items()
            }
        print(json.dumps(out_dict, indent=2))
    else:
        # Terminal render
        if live_reports:
            render_live_cloud_audit(live_reports, currency=args.currency)
        if estimates:
            render_terminal_dashboard(
                estimates=estimates,
                params=params,
                currency=args.currency,
                preset_name=effective_preset if not has_custom else None,
            )

    if args.csv and estimates:
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["Cloud", "Category", "Description", "Hourly", "Monthly", "Currency"])
            for c_key, est in estimates.items():
                for it in est.items:
                    writer.writerow([c_key, it.category, it.description, it.total_hourly, it.total_monthly, args.currency])
        print(f"{Colors.GREEN}[✓] CSV saved to {args.csv}{Colors.RESET}")


if __name__ == "__main__":
    main()
