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
        --quick|--fast|--lightweight)
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

# BuildKit & Parallel Resource Constraints (optimized for budget EC2 & local VMs)
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
export COMPOSE_PARALLEL_LIMIT=2

run_compose() {
    if docker compose version >/dev/null 2>&1; then
        if docker ps >/dev/null 2>&1; then
            docker compose "$@"
        else
            sudo -E docker compose "$@"
        fi
    elif docker-compose version >/dev/null 2>&1; then
        if docker ps >/dev/null 2>&1; then
            docker-compose "$@"
        else
            sudo -E docker-compose "$@"
        fi
    else
        sudo -E docker compose "$@"
    fi
}

detect_host_ip() {
    local host_ip="localhost"
    if command -v curl >/dev/null 2>&1; then
        # Check AWS EC2 IMDSv1
        local ec2_ip
        ec2_ip=$(curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
        if [ -n "$ec2_ip" ] && [[ "$ec2_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            host_ip="$ec2_ip"
        else
            # Check public external IP
            local ext_ip
            ext_ip=$(curl -s --connect-timeout 2 https://ifconfig.me 2>/dev/null || curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || true)
            if [ -n "$ext_ip" ] && [[ "$ext_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                host_ip="$ext_ip"
            fi
        fi
    fi
    echo "$host_ip"
}

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
# MODE 2: DOCKER COMPOSE LOCAL / FULL MULTI-CLOUD PLATFORM
# ==============================================================================
elif [ "$TARGET_MODE" = "compose" ]; then
    echo -e "${YELLOW}[*] Target Mode:${NC} ${BOLD}Full Simulated Multi-Cloud Stack (Docker Compose)${NC}"
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Docker is required for Docker Compose deployment.${NC}"
        exit 1
    fi

    COMPOSE_FILE="${SCRIPT_DIR}/docker/docker-compose.yml"
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${RED}[ERROR] Compose file not found at ${COMPOSE_FILE}${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[*] Building and starting simulated multi-cloud environment (BuildKit accelerated)...${NC}"
    run_compose -f "$COMPOSE_FILE" up -d --build

    DISPLAY_IP=$(detect_host_ip)

    echo -e "\n${GREEN}${BOLD}[✓] Platform services are active & operational:${NC}"
    echo -e "  • Industrial Cockpit Frontend (Next.js 15):  ${BOLD}http://${DISPLAY_IP}:3000${NC} (or http://localhost:3000)"
    echo -e "  • Telemetry Gateway & Controller (Go):       ${BOLD}http://${DISPLAY_IP}:8085${NC}"
    echo -e "  • Low-Latency Edge SIMD Ingestor (Rust):     ${BOLD}http://${DISPLAY_IP}:8082${NC}"
    echo -e "  • Primary AI Inference API (AWS us-east-1):   ${BOLD}http://${DISPLAY_IP}:8000${NC}"
    echo -e "  • Failover AI Inference API (GCP us-central1): ${BOLD}http://${DISPLAY_IP}:8001${NC}"
    echo -e "  • MLflow Tracking & Model Registry:          ${BOLD}http://${DISPLAY_IP}:5000${NC}"
    echo -e "  • MinIO S3 Object Storage Console:           ${BOLD}http://${DISPLAY_IP}:9001${NC} (admin / minioadminpassword)"
    echo -e "  • Health Prober & Failover Daemon:           Active in background"
    echo -e "\n${CYAN}To view live frontend: open http://${DISPLAY_IP}:3000${NC}"
    echo -e "${CYAN}To view live predictions: curl -s http://${DISPLAY_IP}:8000/health | jq .${NC}"
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
# MODE 4: QUICKSTART LIGHTWEIGHT MICROSERVICES (<30s, <1GB RAM)
# ==============================================================================
elif [ "$TARGET_MODE" = "quick" ]; then
    echo -e "${YELLOW}[*] Target Mode:${NC} ${BOLD}Lightweight Core Microservices (Sub-30s Boot, <1GB RAM)${NC}"
    
    COMPOSE_FILE="${SCRIPT_DIR}/docker/docker-compose.yml"
    if command -v docker >/dev/null 2>&1 && [ -f "$COMPOSE_FILE" ]; then
        echo -e "${YELLOW}[*] Launching core microservices via Docker Compose...${NC}"
        run_compose -f "$COMPOSE_FILE" up -d --build frontend gateway-go ingest-rust api-primary redis
        
        DISPLAY_IP=$(detect_host_ip)
        echo -e "\n${GREEN}${BOLD}[✓] Core Microservices are active:${NC}"
        echo -e "  • Industrial Cockpit Frontend (Next.js 15):  ${BOLD}http://${DISPLAY_IP}:3000${NC} (or http://localhost:3000)"
        echo -e "  • Telemetry Gateway & Controller (Go):       ${BOLD}http://${DISPLAY_IP}:8085${NC}"
        echo -e "  • Low-Latency Edge SIMD Ingestor (Rust):     ${BOLD}http://${DISPLAY_IP}:8082${NC}"
        echo -e "  • Primary AI Inference API (AWS us-east-1):   ${BOLD}http://${DISPLAY_IP}:8000${NC}"
        echo -e "  • Redis Telemetry & Semantic Cache:          ${BOLD}localhost:6379${NC}"
        echo -e "\n${CYAN}To teardown: ./clear.sh or make compose-down${NC}\n"
    else
        PYTHON_BIN="python3"
        [ -f "${SCRIPT_DIR}/.venv/bin/python3" ] && PYTHON_BIN="${SCRIPT_DIR}/.venv/bin/python3"
        echo -e "${GREEN}[✓] Starting Smart Manufacturing Application Server...${NC}"
        PORT=8000 $PYTHON_BIN application.py &
        APP_PID=$!
        echo -e "${GREEN}[✓] Application running on http://localhost:8000 (PID: $APP_PID)${NC}"
    fi
fi
