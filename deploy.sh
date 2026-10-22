#!/usr/bin/env bash
# ==============================================================================
# ONE-CLICK AUTONOMOUS DEPLOYMENT RUNNER FOR SMART MANUFACTURING PLATFORM
# Supports:
# 1. On-Host / EC2 / VM Mode: Deploys all platform tools directly on current host
#    (Docker, K3s, Jenkins, SonarQube, Nexus, ArgoCD, Prometheus, Grafana, EFK, Redis, AI API)
# 2. Local Docker Compose Mode: Simulated multi-cloud stack (MinIO, MLflow, APIs, Redis)
# 3. Production GKE Mode: Google Kubernetes Engine VPC-native GPU cluster + GitOps
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR"

show_help() {
    cat << EOF
${CYAN}${BOLD}Smart Manufacturing Industrial AI & MLOps Deployment Runner${NC}

Usage: ./deploy.sh [OPTIONS]

Options:
  (no args)             Auto-detect environment:
                        - On EC2 / Linux VM: Deploys full enterprise DevOps toolchain on host
                        - On macOS / Local:  Launches local Docker Compose platform
  --host, --vm          Deploy full enterprise toolchain on the current Linux host (Docker, K8s, Jenkins,
                        SonarQube, Nexus, ArgoCD, Prometheus, Grafana, EFK, Redis, AI Inference API)
  --compose, --local    Start local simulated multi-cloud environment via Docker Compose (MinIO, MLflow, APIs)
  --gke, --production   Deploy enterprise production stack to Google Kubernetes Engine (GKE)
  --quick               Lightweight quick-start (Smart Mfg App + Redis + Prometheus + Grafana)
  -h, --help            Show this help message

Examples:
  # On any EC2 instance (Ubuntu/Debian) - one-click full deployment:
  ./deploy.sh

  # Local testing with Docker Compose:
  ./deploy.sh --compose

  # Deploy to Google Kubernetes Engine:
  ./deploy.sh --gke
EOF
}

# Parse CLI arguments
TARGET_MODE="auto"
FILTERED_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --gke|--production|-p|--prod)
            TARGET_MODE="gke"
            ;;
        --vm|--host|--devops-vm|--management-vm)
            TARGET_MODE="host"
            ;;
        --compose|--local|-c)
            TARGET_MODE="compose"
            ;;
        --quick)
            TARGET_MODE="quick"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            FILTERED_ARGS+=("$arg")
            ;;
    esac
done

IS_LINUX=false
IS_DARWIN=false
if [ "$(uname -s)" = "Linux" ]; then
    IS_LINUX=true
elif [ "$(uname -s)" = "Darwin" ]; then
    IS_DARWIN=true
fi

# Detect environment if auto
if [ "$TARGET_MODE" = "auto" ]; then
    if [ "$IS_LINUX" = true ]; then
        TARGET_MODE="host"
    else
        TARGET_MODE="compose"
    fi
fi

echo -e "${CYAN}${BOLD}"
cat << "EOF"
================================================================================
   SMART MANUFACTURING INDUSTRIAL AI & MULTI-CLOUD MLOPS PLATFORM
   Automated Deployment Runner
================================================================================
EOF
echo -e "${NC}"

# ==============================================================================
# MODE 1: ON-HOST / EC2 / VM DEPLOYMENT
# ==============================================================================
if [ "$TARGET_MODE" = "host" ]; then
    echo -e "${YELLOW}[*] Target Mode:${NC} ${BOLD}On-Host Enterprise Deployment (EC2 / Ubuntu / Debian)${NC}"

    if [ "$IS_LINUX" != true ]; then
        echo -e "${RED}[ERROR] On-host installation is intended for Linux (Ubuntu / Debian / EC2).${NC}"
        echo -e "${YELLOW}[*] To run on macOS, use: ./deploy.sh --compose${NC}"
        exit 1
    fi

    # Ensure running with sudo if not root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}[*] Escalating privileges to root with sudo for system package configuration...${NC}"
        exec sudo bash "$0" --host "${FILTERED_ARGS[@]}"
    fi

    # Execute on-host installer script
    if [ -f "${SCRIPT_DIR}/scripts/install-ubuntu-tools.sh" ]; then
        bash "${SCRIPT_DIR}/scripts/install-ubuntu-tools.sh" "${FILTERED_ARGS[@]}"
    elif [ -f "${SCRIPT_DIR}/scripts/setup-devops-vm.sh" ]; then
        bash "${SCRIPT_DIR}/scripts/setup-devops-vm.sh" "${FILTERED_ARGS[@]}"
    else
        echo -e "${RED}[ERROR] Neither install-ubuntu-tools.sh nor setup-devops-vm.sh found in scripts/.${NC}"
        exit 1
    fi

# ==============================================================================
# MODE 2: DOCKER COMPOSE LOCAL PLATFORM
# ==============================================================================
elif [ "$TARGET_MODE" = "compose" ]; then
    echo -e "${YELLOW}[*] Target Mode:${NC} ${BOLD}Local Simulated Multi-Cloud (Docker Compose)${NC}"
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Docker is required for Docker Compose deployment.${NC}"
        exit 1
    fi

    COMPOSE_FILE="${SCRIPT_DIR}/docker/docker-compose.yml"
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${RED}[ERROR] Compose file not found at ${COMPOSE_FILE}${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[*] Building and starting local simulated multi-cloud environment...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d --build

    echo -e "\n${GREEN}${BOLD}[✓] Local platform services are active:${NC}"
    echo -e "  • Industrial Cockpit Frontend (Next.js 15):  ${BOLD}http://localhost:3000${NC}"
    echo -e "  • Telemetry Gateway & Controller (Go):       ${BOLD}http://localhost:8085${NC}"
    echo -e "  • Low-Latency Edge SIMD Ingestor (Rust):     ${BOLD}http://localhost:8082${NC}"
    echo -e "  • Primary AI Inference API (AWS us-east-1):   ${BOLD}http://localhost:8000${NC}"
    echo -e "  • Failover AI Inference API (GCP us-central1): ${BOLD}http://localhost:8001${NC}"
    echo -e "  • MLflow Tracking & Model Registry:          ${BOLD}http://localhost:5000${NC}"
    echo -e "  • MinIO S3 Object Storage Console:           ${BOLD}http://localhost:9001${NC} (admin / minioadminpassword)"
    echo -e "  • Health Prober & Failover Daemon:           Active in background"
    echo -e "\n${CYAN}To view live frontend: open http://localhost:3000${NC}"
    echo -e "${CYAN}To view live predictions: curl -s http://localhost:8000/health | jq .${NC}"
    echo -e "${CYAN}To teardown: ./clear.sh or make compose-down${NC}\n"

# ==============================================================================
# MODE 3: GOOGLE KUBERNETES ENGINE (GKE)
# ==============================================================================
elif [ "$TARGET_MODE" = "gke" ]; then
    echo -e "${YELLOW}[*] Target Mode:${NC} ${BOLD}Enterprise Google Kubernetes Engine (GKE)${NC}"
    if ! command -v gcloud >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] 'gcloud' CLI is required for GKE deployment.${NC}"
        exit 1
    fi
    bash "${SCRIPT_DIR}/scripts/setup-gke-production.sh" "${FILTERED_ARGS[@]}"

# ==============================================================================
# MODE 4: QUICKSTART (APP + REDIS + PROMETHEUS + GRAFANA)
# ==============================================================================
elif [ "$TARGET_MODE" = "quick" ]; then
    echo -e "${YELLOW}[*] Target Mode:${NC} ${BOLD}Quick-Start Microservices${NC}"
    if command -v docker >/dev/null 2>&1; then
        docker run -d --name smart-mfg-redis -p 6379:6379 redis:7.2-alpine 2>/dev/null || true
    fi
    PYTHON_BIN="python3"
    [ -f "${SCRIPT_DIR}/.venv/bin/python3" ] && PYTHON_BIN="${SCRIPT_DIR}/.venv/bin/python3"
    echo -e "${GREEN}[✓] Starting Smart Manufacturing Application Server...${NC}"
    PORT=8000 $PYTHON_BIN application.py &
    APP_PID=$!
    echo -e "${GREEN}[✓] Application running on http://localhost:8000 (PID: $APP_PID)${NC}"
fi
