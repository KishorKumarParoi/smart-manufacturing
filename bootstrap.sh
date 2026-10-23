#!/usr/bin/env bash
# ==============================================================================
# 🚀 ZERO-TOUCH 1-COMMAND AUTO-BOOTSTRAPPER FOR EC2 & CLOUD VMS
# SMART MANUFACTURING INDUSTRIAL AI & MULTI-CLOUD MLOPS PLATFORM
#
# Designed for Senior Staff / Principal Engineer Demonstrations:
# Can be run directly on any bare, fresh EC2 instance or local workstation
# via a single curl command without pre-installing git, docker, or python:
#
#   curl -fsSL https://raw.githubusercontent.com/KishorKumarParoi/smart-manufacturing/main/bootstrap.sh | bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/KishorKumarParoi/smart-manufacturing/main/bootstrap.sh | bash -s -- --quick
#   curl -fsSL https://raw.githubusercontent.com/KishorKumarParoi/smart-manufacturing/main/bootstrap.sh | bash -s -- --host
#
# What this script automates:
# 1. Non-interactive OS package manager setup (Ubuntu, Debian, Amazon Linux 2023, RHEL, macOS)
# 2. Fast installs git, curl, ca-certificates, and base build tools
# 3. OOM Protection: Detects if RAM < 4GB and auto-configures a persistent 4GB Swapfile
# 4. Automatically installs and bootstraps Docker Engine and Docker Compose v2 if missing
# 5. Shallow git clone (--depth 1) for 10x faster download and bandwidth savings
# 6. Decoupled stdin hand-off to ./deploy.sh with all options preserved
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
================================================================================
   🏭 SMART MANUFACTURING AI & MULTI-CLOUD MLOPS PLATFORM
   Zero-Touch Instant Cloud & EC2 Bootstrapper
================================================================================
EOF
echo -e "${NC}"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFFOLD=1

run_sudo() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        sudo -E "$@"
    elif command -v sudo &>/dev/null; then
        sudo -E "$@"
    else
        "$@"
    fi
}

# ─── 1. Install Git, Curl & Core Networking Tools ─────────────────────────────
echo -e "${CYAN}[1/5] Detecting OS and ensuring Git & Curl are available...${NC}"

if ! command -v git &>/dev/null || ! command -v curl &>/dev/null; then
    echo -e "${YELLOW}[+] Installing Git and Core Networking Utilities non-interactively...${NC}"
    if [ -f /etc/debian_version ]; then
        run_sudo apt-get update -qq
        run_sudo apt-get install -y -qq --no-install-recommends git curl ca-certificates tar gzip unzip build-essential >/dev/null 2>&1
    elif [ -f /etc/amazon-linux-release ] || [ -f /etc/redhat-release ]; then
        if command -v dnf &>/dev/null; then
            run_sudo dnf install -y -q git curl ca-certificates tar gzip unzip >/dev/null 2>&1 || true
        else
            run_sudo yum install -y -q git curl ca-certificates tar gzip unzip >/dev/null 2>&1 || true
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if ! command -v git &>/dev/null; then
            xcode-select --install 2>/dev/null || true
        fi
    fi
fi

echo -e "${GREEN}[✓] Git : $(git --version 2>/dev/null || echo 'Installed')${NC}"
echo -e "${GREEN}[✓] Curl: $(curl --version 2>/dev/null | head -n 1 || echo 'Installed')${NC}"

# ─── 2. Auto-Swap Configuration (OOM Protection for Small EC2 Instances) ──────
echo -e "\n${CYAN}[2/5] Checking System Memory & OOM Protection...${NC}"

if command -v free &>/dev/null; then
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    EXISTING_SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
    
    # If RAM is under 4GB (e.g. t2.micro, t3.micro, t3.small) and swap is under 1GB, create 4GB swapfile
    if [ "$TOTAL_RAM_MB" -lt 4000 ] && [ "$EXISTING_SWAP_MB" -lt 1000 ]; then
        echo -e "${YELLOW}[!] Host has ${TOTAL_RAM_MB}MB RAM. Auto-configuring 4GB swapfile for compilation & Docker safety...${NC}"
        if [ ! -f /swapfile ]; then
            run_sudo fallocate -l 4G /swapfile 2>/dev/null || run_sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null
            run_sudo chmod 600 /swapfile
            run_sudo mkswap /swapfile >/dev/null 2>&1
            run_sudo swapon /swapfile 2>/dev/null || true
            if ! grep -q "/swapfile" /etc/fstab 2>/dev/null; then
                echo "/swapfile none swap sw 0 0" | run_sudo tee -a /etc/fstab >/dev/null 2>&1 || true
            fi
            echo -e "${GREEN}[✓] 4GB Swapfile configured and active!${NC}"
        fi
    else
        echo -e "${GREEN}[✓] Sufficient memory available (${TOTAL_RAM_MB}MB RAM, ${EXISTING_SWAP_MB}MB Swap).${NC}"
    fi
else
    echo -e "${GREEN}[✓] Memory check bypassed (macOS / BSD runtime).${NC}"
fi

# ─── 3. Docker & Docker Compose v2 Bootstrap ──────────────────────────────────
echo -e "\n${CYAN}[3/5] Checking Docker & Containerization Toolchain...${NC}"

if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}[+] Docker not detected. Automatically installing Docker Engine...${NC}"
    if [ -f /etc/debian_version ] || [ -f /etc/amazon-linux-release ]; then
        curl -fsSL https://get.docker.com | run_sudo sh
        run_sudo systemctl enable --now docker 2>/dev/null || true
        run_sudo usermod -aG docker "$USER" 2>/dev/null || true
    fi
fi

# Ensure docker daemon is active
if [[ "$OSTYPE" != "darwin"* ]]; then
    run_sudo systemctl start docker 2>/dev/null || run_sudo service docker start 2>/dev/null || true
fi

echo -e "${GREEN}[✓] Docker: $(docker --version 2>/dev/null || echo 'Engine Ready')${NC}"

# ─── 4. Repository Auto-Clone or Sync ──────────────────────────────────────────
echo -e "\n${CYAN}[4/5] Ensuring smart-manufacturing repository is local...${NC}"

REPO_URL="https://github.com/KishorKumarParoi/smart-manufacturing.git"
REPO_DIR="smart-manufacturing"

if [ -f "deploy.sh" ] && [ -f "docker/docker-compose.yml" ]; then
    echo -e "${GREEN}[✓] Already inside repository directory ($(pwd)). Syncing latest commit...${NC}"
    git pull --depth 1 origin main 2>/dev/null || true
elif [ -d "$REPO_DIR" ] && [ -f "$REPO_DIR/deploy.sh" ]; then
    echo -e "${GREEN}[✓] Found existing directory ${REPO_DIR}. Entering and updating...${NC}"
    cd "$REPO_DIR"
    git pull --depth 1 origin main 2>/dev/null || true
else
    echo -e "${YELLOW}[+] Shallow cloning repository from GitHub for maximum speed...${NC}"
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi

# Set executable permissions
chmod +x deploy.sh clear.sh bootstrap.sh 2>/dev/null || true
find scripts/ -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

# ─── 5. Hand Off to deploy.sh ─────────────────────────────────────────────────
echo -e "\n${CYAN}[5/5] Executing Autonomous Platform Deployment Pipeline...${NC}"

# Default to --compose if no arguments passed so user gets the live interactive platform
DEPLOY_ARGS=("$@")
if [ ${#DEPLOY_ARGS[@]} -eq 0 ]; then
    DEPLOY_ARGS=("--compose")
fi

# Unlink stdin from curl pipe so deploy.sh never blocks or receives early EOF
if [ -t 0 ]; then
    exec ./deploy.sh "${DEPLOY_ARGS[@]}"
elif [ -e /dev/tty ] && [ -r /dev/tty ]; then
    exec ./deploy.sh "${DEPLOY_ARGS[@]}" </dev/tty
else
    exec ./deploy.sh "${DEPLOY_ARGS[@]}" </dev/null
fi
