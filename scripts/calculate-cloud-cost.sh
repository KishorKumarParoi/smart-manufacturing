#!/usr/bin/env bash
# ==============================================================================
# Multi-Cloud Cost Calculator (AWS, GCP, Azure) - Shell Wrapper
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/calculate_cloud_cost.py"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure Python 3 is installed
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Python 3 is required to run the cost calculator.${NC}"
    exit 1
fi

# If arguments are passed, pass them directly to Python script
if [ "$#" -gt 0 ]; then
    python3 "$PYTHON_SCRIPT" "$@"
    exit $?
fi

# Interactive Quick Menu if launched without flags
echo -e "${CYAN}${BOLD}"
cat << "EOF"
================================================================================
   MULTI-CLOUD COST ESTIMATOR & LIVE API FINANCIAL AUDITOR (AWS | GCP | AZURE)
================================================================================
EOF
echo -e "${NC}"
echo -e "Choose an option:"
echo -e "  ${BOLD}1)${NC} ${YELLOW}🔴 Fetch LIVE Cost & Usage from Cloud APIs${NC} (AWS, GCP, Azure real-time burn)"
echo -e "  ${BOLD}2)${NC} ${GREEN}Live Cloud Audit + MLOps Project Architecture${NC} (Combined Live + Model)"
echo -e "  ${BOLD}3)${NC} Calculate cost for ${GREEN}Smart Manufacturing MLOps Project${NC} (EKS / GKE / AKS + GPU)"
echo -e "  ${BOLD}4)${NC} Calculate cost for ${GREEN}Standalone DevOps VM${NC} (Jenkins, ArgoCD, SonarQube, Nexus)"
echo -e "  ${BOLD}5)${NC} Calculate cost for ${GREEN}Kubernetes GPU Cluster${NC} (Training & Triton Inference)"
echo -e "  ${BOLD}6)${NC} Calculate cost for ${GREEN}Minimal Dev Sandbox${NC} (Budget 8 hrs/day)"
echo -e "  ${BOLD}7)${NC} Export Markdown Report to file (${CYAN}cloud_cost_report.md${NC})"
echo -e "  ${BOLD}8)${NC} Export CSV Spreadsheet to file (${CYAN}cloud_cost_breakdown.csv${NC})"
echo -e "  ${BOLD}9)${NC} Custom parameters / CLI Help (--help)"
echo ""
read -r -p "Enter choice [1-9] (default: 1): " CHOICE
CHOICE="${CHOICE:-1}"

case "$CHOICE" in
    1)
        echo -e "${YELLOW}[*] Querying live cost & usage APIs from AWS, GCP, and Azure...${NC}"
        python3 "$PYTHON_SCRIPT" --live --show-logs
        ;;
    2)
        echo -e "${YELLOW}[*] Querying live cloud APIs and calculating Smart Manufacturing MLOps project model...${NC}"
        python3 "$PYTHON_SCRIPT" --preset project --live --show-logs
        ;;
    3)
        python3 "$PYTHON_SCRIPT" --preset project
        ;;
    4)
        python3 "$PYTHON_SCRIPT" --preset devops-vm
        ;;
    5)
        python3 "$PYTHON_SCRIPT" --preset k8s-gpu
        ;;
    6)
        python3 "$PYTHON_SCRIPT" --preset minimal
        ;;
    7)
        REPORT_FILE="cloud_cost_report.md"
        python3 "$PYTHON_SCRIPT" --preset project --live --markdown > "$REPORT_FILE"
        echo -e "${GREEN}[✓] Markdown report saved to: ${BOLD}${REPORT_FILE}${NC}"
        cat "$REPORT_FILE"
        ;;
    8)
        CSV_FILE="cloud_cost_breakdown.csv"
        python3 "$PYTHON_SCRIPT" --preset project --csv "$CSV_FILE"
        echo -e "${GREEN}[✓] CSV file saved to: ${BOLD}${CSV_FILE}${NC}"
        ;;
    9)
        python3 "$PYTHON_SCRIPT" --help
        ;;
    *)
        python3 "$PYTHON_SCRIPT" --live
        ;;
esac
