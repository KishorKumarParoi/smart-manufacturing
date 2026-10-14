#!/usr/bin/env bash
# ==============================================================================
# ONE-CLICK AUTONOMOUS DEPLOYMENT RUNNER FOR SMART MANUFACTURING DEVOPS PLATFORM
# Supports:
# 1. Production Mode: Enterprise Google Kubernetes Engine (GKE) + GitOps
# 2. Management VM Mode: Dedicated CI/CD VM (Jenkins, Nexus, SonarQube)
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

USE_GKE=false
FILTERED_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --gke|--production|-p|--prod)
            USE_GKE=true
            ;;
        --vm|--devops-vm|--management-vm)
            USE_GKE=false
            ;;
        *)
            FILTERED_ARGS+=("$arg")
            ;;
    esac
done

# If on the production git branch, default to GKE enterprise deployment unless explicitly --vm
if [ "$CURRENT_BRANCH" = "production" ] && [ "$USE_GKE" != false ]; then
    USE_GKE=true
fi

if [ "$USE_GKE" = true ]; then
    echo "[*] Production Environment Active: Deploying to Google Kubernetes Engine (GKE)..."
    bash "${SCRIPT_DIR}/scripts/setup-gke-production.sh" "${FILTERED_ARGS[@]}"
else
    # Run DevOps Management VM Provisioning & Setup
    if [[ "$OSTYPE" == "darwin"* ]] || [ "$EUID" -ne 0 ]; then
        bash "${SCRIPT_DIR}/scripts/install-ubuntu-tools.sh" --provision-vm "${FILTERED_ARGS[@]}"
    else
        sudo bash "${SCRIPT_DIR}/scripts/install-ubuntu-tools.sh" "${FILTERED_ARGS[@]}"
    fi
fi
