#!/usr/bin/env bash
set -eo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE} Smart Manufacturing Platform - Environment Check         ${NC}"
echo -e "${BLUE}==========================================================${NC}"

check_tool() {
    local tool=$1
    local name=$2
    if command -v "$tool" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] $name is installed:$(NC) $(which $tool)"
    else
        echo -e "${RED}[✗] $name is NOT installed.${NC}"
    fi
}

check_tool "python3" "Python 3"
check_tool "docker" "Docker"
check_tool "kubectl" "Kubectl"
check_tool "helm" "Helm"
check_tool "terraform" "Terraform"
check_tool "ansible" "Ansible"
check_tool "aws" "AWS CLI"
check_tool "gcloud" "Google Cloud SDK"
check_tool "gh" "GitHub CLI"
check_tool "make" "Make"

echo -e "\n${YELLOW}[*] Checking PyTorch & GPU compute support...${NC}"
python3 -c "import torch; print(f'PyTorch: {torch.__version__} | CUDA Available: {torch.cuda.is_available()} | MPS Available: {torch.backends.mps.is_available()}')" 2>/dev/null || echo "[!] PyTorch not yet installed in active python interpreter"

echo -e "\n${GREEN}[✓] Environment check completed!${NC}"
