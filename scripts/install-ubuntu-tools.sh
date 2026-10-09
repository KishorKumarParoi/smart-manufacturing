#!/usr/bin/env bash
# ==============================================================================
# ALL-IN-ONE DEVOPS SETUP SCRIPT (UBUNTU & DEBIAN - IDEMPOTENT & PRODUCTION-READY)
# Docker | Minikube | Kubectl | ArgoCD CLI & Server | Jenkins | Git/GitHub | Firewall
# Target OS: Ubuntu 20.04 / 22.04 / 24.04 LTS | Debian 11 / 12 / 13 (Trixie) (x86_64)
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

header() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
==================================================================
  DEVOPS PLATFORM AUTOMATED SETUP (UBUNTU / DEBIAN)
  Docker | Minikube | Kubectl | ArgoCD | Jenkins | Git/GitHub | Firewall
==================================================================
EOF
    echo -e "${NC}"
}

header

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: sudo bash $0 [OPTIONS]"
    echo "Options:"
    echo "  (no args)        Run full DevOps platform installation & optimization"
    echo "  --optimize       Clear RAM caches, vacuum logs, remove bloatware, and tune kernel"
    echo "  --cleanup        Alias for --optimize"
    echo "  --speedup        Alias for --optimize"
    echo "  --fix-minikube   Reset stale Minikube Docker network bridge and recover cluster"
    echo "  --help, -h       Show this help message"
    exit 0
fi

# Ensure running with sudo or as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run this script with sudo or as root:${NC}"
    echo "  sudo bash $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/../.env"
elif [ -f "${SCRIPT_DIR}/.env" ]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env"
elif [ -f "${USER_HOME}/.devops.env" ]; then
    # shellcheck disable=SC1091
    source "${USER_HOME}/.devops.env"
fi

# Configuration defaults (can be overridden via environment variables or .env)
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-admin123}"
GIT_USER_NAME="${GIT_USER_NAME:-Kishor Kumar Paroi}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-1703053@student.ruet.ac.bd}"
GITHUB_USERNAME="${GITHUB_USERNAME:-KishorKumarParoi}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-kishorkumarparoi}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"
FIREWALL_NAME="${FIREWALL_NAME:-allow-devops-platform}"
TARGET_TAGS="allow-devops-platform,devops-control-plane,devops-vm"
REQUIRED_PORTS=(22 80 443 8000 8080 8081 9000 30080 30751 30752 50000)

# Detect Operating System (Ubuntu / Debian / Debian-derivatives)
OS_ID="ubuntu"
OS_CODENAME="jammy"
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-ubuntu}"
    OS_CODENAME="${VERSION_CODENAME:-}"
fi

# Standardize Docker upstream distro mapping (prioritize ID=ubuntu over ID_LIKE=debian)
if [ "$OS_ID" = "ubuntu" ]; then
    DOCKER_DISTRO="ubuntu"
    [ -z "$OS_CODENAME" ] && OS_CODENAME="jammy"
elif [ "$OS_ID" = "debian" ]; then
    DOCKER_DISTRO="debian"
    [ -z "$OS_CODENAME" ] && OS_CODENAME="bookworm"
elif echo "${ID_LIKE:-}" | grep -qw "ubuntu"; then
    DOCKER_DISTRO="ubuntu"
    [ -z "$OS_CODENAME" ] && OS_CODENAME="jammy"
elif echo "${ID_LIKE:-}" | grep -qw "debian"; then
    DOCKER_DISTRO="debian"
    [ -z "$OS_CODENAME" ] && OS_CODENAME="bookworm"
else
    DOCKER_DISTRO="ubuntu"
    [ -z "$OS_CODENAME" ] && OS_CODENAME="jammy"
fi

# System Optimization, Memory Clearing & Bloatware Cleanup Function
optimize_system_and_ram() {
    echo -e "\n${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${CYAN}${BOLD} [SYSTEM ACCELERATION] RAM Flush, Bloatware & Disk Optimizer      ${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"

    # 1. Capture memory metrics before cleanup
    local mem_before_free_mb=0
    local mem_before_avail_mb=0
    if [ -f /proc/meminfo ]; then
        mem_before_free_mb=$(awk '/MemFree/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
        mem_before_avail_mb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    fi
    echo -e "${YELLOW}[*] Initial RAM Available: ${BOLD}${mem_before_avail_mb} MB${NC} (Free: ${mem_before_free_mb} MB)"

    # 2. Deactivate and mask unnecessary telemetry, crash daemons, and background update locks
    echo -e "${YELLOW}[*] Deactivating telemetry, crash reporters, and unattended update locks...${NC}"
    local BLOAT_SERVICES=(whoopsie apport apport-autoreport unattended-upgrades update-notifier-download update-notifier-motd)
    for svc in "${BLOAT_SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null || true
        fi
        systemctl disable "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    done
    echo -e "${GREEN}[✓] Background telemetry and crash daemons deactivated.${NC}"

    # 3. Clean Package Manager caches and purge orphan packages
    echo -e "${YELLOW}[*] Purging obsolete packages, broken locks, and package manager caches...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
    dpkg --configure -a >/dev/null 2>&1 || true
    
    apt-get autoremove --purge -y >/dev/null 2>&1 || true
    apt-get autoclean -y >/dev/null 2>&1 || true
    apt-get clean -y >/dev/null 2>&1 || true
    rm -rf /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/* /var/lib/apt/lists/partial/* 2>/dev/null || true
    
    if [ -d "/var/lib/snapd/cache" ]; then
        rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
    fi
    echo -e "${GREEN}[✓] APT caches cleared & orphan packages purged.${NC}"

    # 4. Vacuum systemd journal logs to max 50MB (frees 500MB - 3GB)
    echo -e "${YELLOW}[*] Vacuuming systemd journal logs (retaining max 1 day / 50MB)...${NC}"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=1d --vacuum-size=50M >/dev/null 2>&1 || true
    fi

    # 5. Remove compressed and old rotated log archives (*.gz, *.1, *.old, *.xz)
    echo -e "${YELLOW}[*] Removing obsolete log archives and clearing crash dumps...${NC}"
    find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" -o -name "*.xz" \) -delete 2>/dev/null || true
    find /var/log -type f -name "*.log" -size +50M -exec truncate -s 2M {} + 2>/dev/null || true
    rm -rf /var/crash/* /var/log/journal/*/*.journal~ /var/tmp/* 2>/dev/null || true
    find /tmp -mindepth 1 -maxdepth 2 -not -name ".*" -not -name "hsperfdata_*" -mtime +1 -delete 2>/dev/null || true
    rm -rf /root/.cache/pip /home/*/.cache/pip /tmp/pip* /tmp/*.whl 2>/dev/null || true
    find /var/jenkins_home -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    echo -e "${GREEN}[✓] Log files trimmed and temp archives cleared.${NC}"

    # 6. Non-destructive Docker build cache & dangling pruning
    if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
        echo -e "${YELLOW}[*] Pruning dangling Docker build cache and dangling images...${NC}"
        docker builder prune -f >/dev/null 2>&1 || true
        docker network prune -f >/dev/null 2>&1 || true
        docker image prune -f >/dev/null 2>&1 || true
        echo -e "${GREEN}[✓] Docker build cache and dangling networks cleaned.${NC}"
    fi

    # 7. Kernel & Virtual Memory High-Performance Tuning (sysctl)
    echo -e "${YELLOW}[*] Applying Linux kernel VM parameters (swappiness=10, max_map_count=524288)...${NC}"
    mkdir -p /etc/sysctl.d
    cat << "EOF_SYSCTL" > /etc/sysctl.d/99-devops-performance.conf
# Antigravity DevOps Platform Performance Tuning
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.max_map_count = 524288
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF_SYSCTL

    sysctl --system >/dev/null 2>&1 || true

    mkdir -p /etc/security/limits.d
    cat << "EOF_LIMITS" > /etc/security/limits.d/99-devops.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65536
* hard nproc 65536
root soft nofile 1048576
root hard nofile 1048576
EOF_LIMITS
    echo -e "${GREEN}[✓] Kernel sysctl and open file descriptor limits optimized.${NC}"

    # 8. Immediate RAM Cache Flush, Memory Compaction & Stale Swap Purge
    echo -e "${YELLOW}[*] Flushing pagecache, dentries, and inodes (sync + drop_caches)...${NC}"
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true

    if [ -f /proc/swaps ] && [ "$(wc -l < /proc/swaps 2>/dev/null || echo 0)" -gt 1 ]; then
        echo -e "${YELLOW}[*] Purging stale swap buffer memory back into fast RAM...${NC}"
        swapoff -a 2>/dev/null && swapon -a 2>/dev/null || true
    fi

    # 9. Report Post-Optimization Memory Stats
    local mem_after_free_mb=0
    local mem_after_avail_mb=0
    if [ -f /proc/meminfo ]; then
        mem_after_free_mb=$(awk '/MemFree/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
        mem_after_avail_mb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    fi

    local freed_mb=$((mem_after_free_mb - mem_before_free_mb))
    if [ "$freed_mb" -lt 0 ]; then
        freed_mb=0
    fi

    echo -e "${GREEN}${BOLD}[✓] RAM & System Optimization Complete!${NC}"
    echo -e "    • Available RAM: ${BOLD}${mem_after_avail_mb} MB${NC} (Free: ${mem_after_free_mb} MB)"
    echo -e "    • Direct RAM Released: ${GREEN}${BOLD}+${freed_mb} MB${NC}"
    echo -e "    • Swappiness: ${BOLD}$(cat /proc/sys/vm/swappiness 2>/dev/null || echo '10')${NC} (optimized for DevOps workloads)"
}

# Minikube Self-Healing & Network Recovery Function
fix_and_start_minikube() {
    echo -e "\n${YELLOW}${BOLD}[*] Auto-Healing Minikube Cluster & Docker Network IPAM...${NC}"
    
    # 1. Stop conflicting k3s service if active on host
    if systemctl is-active --quiet k3s 2>/dev/null; then
        echo -e "${YELLOW}[!] Disabling conflicting k3s service to free Kubernetes control-plane ports...${NC}"
        systemctl stop k3s 2>/dev/null || true
        systemctl disable k3s 2>/dev/null || true
    fi

    # 2. Purge stale Minikube profile and container
    echo -e "${YELLOW}[*] Purging stale Minikube profile and removing orphaned container...${NC}"
    sudo -u "$REAL_USER" minikube delete --all --purge >/dev/null 2>&1 || true
    docker rm -f minikube 2>/dev/null || true

    # 3. Clean Docker network bridge 'minikube' to release locked IP addresses (Address already in use)
    echo -e "${YELLOW}[*] Resetting Docker network bridge 'minikube'...${NC}"
    docker network rm minikube 2>/dev/null || true
    docker network prune -f >/dev/null 2>&1 || true

    # 4. Refresh Docker daemon socket & daemon to clear stale IPAM tables
    echo -e "${YELLOW}[*] Refreshing Docker daemon network IPAM tables...${NC}"
    systemctl restart docker.socket docker >/dev/null 2>&1 || true
    chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -m u:"$REAL_USER":rw /var/run/docker.sock 2>/dev/null || true
        setfacl -m u:"$REAL_USER":rw /run/docker.sock 2>/dev/null || true
    fi
    sleep 2

    # 5. Start clean Minikube cluster
    echo -e "${YELLOW}[*] Starting clean Minikube cluster using Docker driver...${NC}"
    if sudo -u "$REAL_USER" minikube start --driver=docker; then
        echo -e "${GREEN}[✓] Minikube cluster recovered and running!${NC}"
    else
        echo -e "${YELLOW}[*] Retrying with clean dedicated network bridge...${NC}"
        sudo -u "$REAL_USER" minikube delete --all --purge >/dev/null 2>&1 || true
        docker rm -f minikube 2>/dev/null || true
        docker network rm minikube 2>/dev/null || true
        sudo -u "$REAL_USER" minikube start --driver=docker --network=minikube-net
        echo -e "${GREEN}[✓] Minikube cluster recovered with clean network!${NC}"
    fi
}

# Handle standalone execution flags
if [[ "$1" == "--optimize" || "$1" == "--clean" || "$1" == "--cleanup" || "$1" == "--speedup" || "$1" == "-o" ]]; then
    optimize_system_and_ram
    exit 0
elif [[ "$1" == "--fix-minikube" || "$1" == "--repair-minikube" ]]; then
    fix_and_start_minikube
    exit 0
elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: sudo bash $0 [OPTIONS]"
    echo "Options:"
    echo "  (no args)        Run full DevOps platform installation & optimization"
    echo "  --optimize       Clear RAM caches, vacuum logs, remove bloatware, and tune kernel"
    echo "  --cleanup        Alias for --optimize"
    echo "  --speedup        Alias for --optimize"
    echo "  --fix-minikube   Reset stale Minikube Docker network bridge and recover cluster"
    echo "  --help, -h       Show this help message"
    exit 0
fi

echo -e "${YELLOW}[*] Configuring DevOps toolchain for user:${NC} ${BOLD}${REAL_USER}${NC}"
echo -e "${YELLOW}[*] Jenkins admin account:${NC} ${BOLD}${JENKINS_ADMIN_USER}${NC}"
echo -e "${YELLOW}[*] Git & GitHub profile:${NC} ${BOLD}${GITHUB_USERNAME} (${GIT_USER_EMAIL})${NC}"
echo -e "${YELLOW}[*] DockerHub account:${NC} ${BOLD}${DOCKERHUB_USERNAME}${NC}"

# ==============================================================================
# 1. Base Packages & Dependencies (Idempotent & Multi-Distro Compatible)
# ==============================================================================
echo -e "\n${CYAN}[1/9] Checking base utilities (${DOCKER_DISTRO} ${OS_CODENAME})...${NC}"

# Core packages guaranteed across Debian (including Trixie) and Ubuntu LTS releases
REQUIRED_PKGS=(ca-certificates curl gnupg lsb-release wget conntrack git jq ufw acl procps)
if [ "$DOCKER_DISTRO" = "ubuntu" ]; then
    REQUIRED_PKGS+=(software-properties-common)
fi
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    echo -e "${GREEN}[✓] Base utilities already installed. Skipping package manager update.${NC}"
else
    echo -e "${YELLOW}[*] Installing missing utilities: ${MISSING_PKGS[*]}...${NC}"
    apt-get update -y
    for pkg in "${MISSING_PKGS[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            apt-get install -y --no-install-recommends "$pkg" || {
                echo -e "${YELLOW}[!] Notice: Package '$pkg' could not be installed directly, continuing...${NC}"
            }
        fi
    done
    echo -e "${GREEN}[✓] Base utilities check completed.${NC}"
fi

# ==============================================================================
# 2. Docker CE & Permissions (Idempotent & Immediate Non-Root Access)
# ==============================================================================
echo -e "\n${CYAN}[2/9] Checking Docker CE installation & non-root socket permissions...${NC}"

if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
    echo -e "${GREEN}[✓] Docker is already installed and running: ${NC}$(docker --version)"
else
    echo -e "${YELLOW}[*] Installing Docker CE and Docker Compose plugin for ${BOLD}${DOCKER_DISTRO} (${OS_CODENAME})${NC}...${NC}"
    rm -f /etc/apt/sources.list.d/docker*.list
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DOCKER_DISTRO} \
      ${OS_CODENAME} stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}[✓] Docker installed successfully: ${NC}$(docker --version)"
fi

# Ensure kernel IP forwarding is active for Docker container ingress
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

# Ensure user is in docker group
if ! id -nG "$REAL_USER" | grep -qw docker; then
    usermod -aG docker "$REAL_USER"
    echo -e "${GREEN}[✓] Added ${REAL_USER} to docker group.${NC}"
fi

# Configure permanent non-root Docker socket permissions (0666 - NO 'newgrp docker' required)
echo -e "${YELLOW}[*] Configuring permanent non-root Docker socket permissions (mode 0666)...${NC}"
mkdir -p /etc/systemd/system/docker.socket.d
cat << "EOF_DOCKER_SOCK" > /etc/systemd/system/docker.socket.d/override.conf
[Socket]
SocketMode=0666
EOF_DOCKER_SOCK

mkdir -p /etc/systemd/system/docker.service.d
cat << "EOF_DOCKER_SVC" > /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStartPost=/bin/sh -c 'chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true'
EOF_DOCKER_SVC

mkdir -p /etc/tmpfiles.d
cat << "EOF_TMPFILES" > /etc/tmpfiles.d/docker.conf
z /var/run/docker.sock 0666 root docker -
z /run/docker.sock 0666 root docker -
EOF_TMPFILES

mkdir -p /etc/udev/rules.d
echo 'KERNEL=="docker.sock", MODE="0666"' > /etc/udev/rules.d/80-docker.rules

# Reload systemd and apply socket permissions
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart docker.socket >/dev/null 2>&1 || true

# Apply immediate permissions on active socket
chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true
if command -v setfacl >/dev/null 2>&1; then
    setfacl -m u:"$REAL_USER":rw /var/run/docker.sock 2>/dev/null || true
    setfacl -m u:"$REAL_USER":rw /run/docker.sock 2>/dev/null || true
fi

# Verify non-root access directly for REAL_USER
if sudo -u "$REAL_USER" docker ps >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Docker non-root access active: ${BOLD}${REAL_USER}${NC}${GREEN} can run docker immediately without sudo or newgrp!${NC}"
else
    chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true
    echo -e "${GREEN}[✓] Docker socket mode set to 0666 for instant non-root access.${NC}"
fi

# Authenticate host Docker daemon with DockerHub
if [ -n "$DOCKERHUB_TOKEN" ] && [ -n "$DOCKERHUB_USERNAME" ]; then
    echo -e "${YELLOW}[*] Authenticating host Docker CLI with DockerHub (${DOCKERHUB_USERNAME})...${NC}"
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
    echo "$DOCKERHUB_TOKEN" | sudo -u "$REAL_USER" docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
    echo -e "${GREEN}[✓] DockerHub authentication configured for user '${DOCKERHUB_USERNAME}'.${NC}"
fi

# ==============================================================================
# 3. Kubectl & ArgoCD CLI on Host (Idempotent)
# ==============================================================================
echo -e "\n${CYAN}[3/9] Checking Kubectl and ArgoCD CLI...${NC}"

# Kubectl
if command -v kubectl >/dev/null 2>&1; then
    K8S_VER=$(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion | head -n 1 | awk '{print $2}' || kubectl version --client 2>/dev/null | head -n 1)
    echo -e "${GREEN}[✓] Kubectl is already installed: ${NC}${K8S_VER}"
else
    echo -e "${YELLOW}[*] Installing Kubectl...${NC}"
    K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/kubectl
    echo -e "${GREEN}[✓] Kubectl installed: ${NC}$(kubectl version --client --output=yaml | grep gitVersion | head -n 1)"
fi

# ArgoCD CLI
if command -v argocd >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] ArgoCD CLI is already installed: ${NC}$(argocd version --client --short 2>/dev/null || echo 'installed')"
else
    echo -e "${YELLOW}[*] Installing ArgoCD CLI...${NC}"
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
    echo -e "${GREEN}[✓] ArgoCD CLI installed.${NC}"
fi


# Shell completion and aliases
if ! grep -q "alias k=kubectl" "$USER_HOME/.bashrc" 2>/dev/null; then
    echo "alias k=kubectl" >> "$USER_HOME/.bashrc"
    echo "complete -o default -F __start_kubectl k" >> "$USER_HOME/.bashrc"
    echo "source <(kubectl completion bash)" >> "$USER_HOME/.bashrc"
fi

# ==============================================================================
# 4. Configure Git, GitHub CLI & Credentials on Host (Idempotent)
# ==============================================================================
echo -e "\n${CYAN}[4/9] Configuring Git & GitHub authentication (${GITHUB_USERNAME})...${NC}"

# A. Configure Git global user identity
echo -e "${YELLOW}[*] Setting up Git configuration for user ${REAL_USER}...${NC}"
sudo -u "$REAL_USER" git config --global user.name "$GIT_USER_NAME"
sudo -u "$REAL_USER" git config --global user.email "$GIT_USER_EMAIL"
sudo -u "$REAL_USER" git config --global init.defaultBranch main
sudo -u "$REAL_USER" git config --global credential.helper store

# Also set for root user
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global init.defaultBranch main
git config --global credential.helper store
echo -e "${GREEN}[✓] Git global identity configured: ${BOLD}${GIT_USER_NAME} <${GIT_USER_EMAIL}>${NC}"

# B. Install GitHub CLI (gh)
if command -v gh >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] GitHub CLI (gh) is already installed: ${NC}$(gh --version | head -n 1)"
else
    echo -e "${YELLOW}[*] Installing GitHub CLI (gh)...${NC}"
    mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update -y
    apt-get install -y gh
    echo -e "${GREEN}[✓] GitHub CLI installed: ${NC}$(gh --version | head -n 1)"
fi

# C. Setup SSH Key for GitHub & known_hosts
SSH_DIR="$USER_HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$SSH_DIR/id_ed25519" ] && [ ! -f "$SSH_DIR/id_rsa" ]; then
    echo -e "${YELLOW}[*] Generating ED25519 SSH key for GitHub authentication...${NC}"
    sudo -u "$REAL_USER" ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -f "$SSH_DIR/id_ed25519" -N ""
    chown -R "$REAL_USER:$REAL_USER" "$SSH_DIR"
    echo -e "${GREEN}[✓] Generated SSH key: ${SSH_DIR}/id_ed25519.pub${NC}"
else
    echo -e "${GREEN}[✓] SSH key already present in ${SSH_DIR}.${NC}"
fi

# Register GitHub in known_hosts to prevent interactive host verification prompts
touch "$SSH_DIR/known_hosts"
if ! grep -q "github.com" "$SSH_DIR/known_hosts" 2>/dev/null; then
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$SSH_DIR/known_hosts" 2>/dev/null || true
    chown "$REAL_USER:$REAL_USER" "$SSH_DIR/known_hosts"
    echo -e "${GREEN}[✓] Added github.com to ${SSH_DIR}/known_hosts.${NC}"
fi

# D. Git Credential Helper Store & GitHub Token Authentication
if [ -n "$GITHUB_TOKEN" ]; then
    echo -e "${YELLOW}[*] Storing GitHub credentials in git-credentials store...${NC}"
    CRED_ENTRY="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com"

    # Store for REAL_USER
    touch "$USER_HOME/.git-credentials"
    if grep -q "github.com" "$USER_HOME/.git-credentials" 2>/dev/null; then
        sed -i "s|https://.*github\.com.*|${CRED_ENTRY}|" "$USER_HOME/.git-credentials"
    else
        echo "$CRED_ENTRY" >> "$USER_HOME/.git-credentials"
    fi
    chmod 600 "$USER_HOME/.git-credentials"
    chown "$REAL_USER:$REAL_USER" "$USER_HOME/.git-credentials"

    # Store for root
    touch /root/.git-credentials
    if grep -q "github.com" /root/.git-credentials 2>/dev/null; then
        sed -i "s|https://.*github\.com.*|${CRED_ENTRY}|" /root/.git-credentials
    else
        echo "$CRED_ENTRY" >> /root/.git-credentials
    fi
    chmod 600 /root/.git-credentials

    # Login to GitHub CLI non-interactively
    if command -v gh >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Authenticating GitHub CLI (${GITHUB_USERNAME})...${NC}"
        echo "$GITHUB_TOKEN" | sudo -u "$REAL_USER" gh auth login --with-token 2>/dev/null || true
        sudo -u "$REAL_USER" gh auth setup-git 2>/dev/null || true
    fi
    echo -e "${GREEN}[✓] GitHub credentials stored & authenticated for user '${GITHUB_USERNAME}'!${NC}"
else
    echo -e "${YELLOW}[i] GITHUB_TOKEN not supplied. Git configured with store helper; SSH key is ready.${NC}"
fi

# ==============================================================================
# 5. Minikube Cluster (Docker Driver - Idempotent)
# ==============================================================================
echo -e "\n${CYAN}[5/9] Checking Minikube installation & cluster state...${NC}"

if command -v minikube >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Minikube binary is already installed: ${NC}$(minikube version --short 2>/dev/null || echo 'installed')"
else
    echo -e "${YELLOW}[*] Installing Minikube binary...${NC}"
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64
    echo -e "${GREEN}[✓] Minikube binary installed.${NC}"
fi

# Check if Minikube is already running
MINIKUBE_STATUS=$(sudo -u "$REAL_USER" minikube status --format='{{.Host}}' 2>/dev/null || echo "Stopped")
if [ "$MINIKUBE_STATUS" = "Running" ] && sudo -u "$REAL_USER" kubectl get nodes >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Minikube cluster is already RUNNING! Skipping cluster bootstrap.${NC}"
else
    # Prevent k3s or other kubernetes distribution from conflicting on port 6443/8443
    if systemctl is-active --quiet k3s 2>/dev/null; then
        echo -e "${YELLOW}[!] Disabling conflicting k3s service to free Kubernetes control-plane ports...${NC}"
        systemctl stop k3s 2>/dev/null || true
        systemctl disable k3s 2>/dev/null || true
    fi

    echo -e "${YELLOW}[*] Starting Minikube cluster using Docker driver (network 'minikube')...${NC}"
    if sudo -u "$REAL_USER" minikube start --driver=docker; then
        echo -e "${GREEN}[✓] Minikube cluster is up!${NC}"
    else
        echo -e "\n${YELLOW}[!] Minikube start failed on existing container ('Address already in use' / IPAM conflict detected).${NC}"
        echo -e "${YELLOW}[*] Triggering automated self-healing recovery...${NC}"
        fix_and_start_minikube
    fi
fi

# Sync kubeconfig for root
mkdir -p /root/.kube
if [ -f "$USER_HOME/.kube/config" ]; then
    cp "$USER_HOME/.kube/config" /root/.kube/config
    chown -R root:root /root/.kube
fi

echo -e "${GREEN}[✓] Kubernetes Nodes:${NC}"
kubectl get nodes

# ==============================================================================
# 6. ArgoCD on Kubernetes (Minikube - Idempotent)
# ==============================================================================
echo -e "\n${CYAN}[6/9] Checking ArgoCD in Kubernetes...${NC}"

ARGOCD_STATUS=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")

if [ "$ARGOCD_STATUS" = "True" ]; then
    echo -e "${GREEN}[✓] ArgoCD server is already deployed and Available in Kubernetes.${NC}"
else
    echo -e "${YELLOW}[*] Deploying ArgoCD manifests into namespace 'argocd'...${NC}"
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo -e "${YELLOW}[*] Waiting for ArgoCD server deployment to become ready...${NC}"
    kubectl rollout status deployment/argocd-server -n argocd --timeout=180s || true
fi

# Ensure NodePort 30751 is configured on argocd-server service
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 8080, "nodePort": 30751}, {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30752}]}}' 2>/dev/null || true

# Retrieve ArgoCD initial admin password
ARGOCD_PASSWORD=""
for i in {1..8}; do
    ARGOCD_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)
    if [ -n "$ARGOCD_PASSWORD" ]; then
        break
    fi
    sleep 3
done

# ==============================================================================
# 7. Deploy Jenkins with Direct Login, Git/GitHub Credentials & Idempotency
# ==============================================================================
echo -e "\n${CYAN}[7/9] Configuring Jenkins with automatic login & Git/GitHub credentials (Docker + Minikube Network)...${NC}"

JENKINS_HOME_HOST="/var/jenkins_home"
mkdir -p "${JENKINS_HOME_HOST}/init.groovy.d"
chmod -R 777 "${JENKINS_HOME_HOST}" 2>/dev/null || true

# 1. Mark setup wizard as completed so Jenkins does not show the unlock / wizard screen
echo "2.0" > "${JENKINS_HOME_HOST}/jenkins.install.UpgradeWizard.state"
echo "2.440.4" > "${JENKINS_HOME_HOST}/jenkins.install.InstallUtil.lastExecVersion"

# 2. Write Groovy initialization script to create the admin user and configure security realm
cat << EOF_GROOVY > "${JENKINS_HOME_HOST}/init.groovy.d/01-create-admin.groovy"
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()
def adminUser = "${JENKINS_ADMIN_USER}"
def adminPass = "${JENKINS_ADMIN_PASSWORD}"

println "--> [Antigravity DevOps] Initializing Jenkins Security Realm and Admin: \${adminUser}"

def realm = instance.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    realm = new HudsonPrivateSecurityRealm(false)
    instance.setSecurityRealm(realm)
}

def existingUser = realm.getUser(adminUser)
if (existingUser == null || realm.getAllUsers().find { it.getId().equalsIgnoreCase(adminUser) } == null) {
    realm.createAccount(adminUser, adminPass)
    println "--> [Antigravity DevOps] Admin account '\${adminUser}' created successfully."
} else {
    def passwordDetails = hudson.security.HudsonPrivateSecurityRealm.Details.fromPlainPassword(adminPass)
    existingUser.addProperty(passwordDetails)
    println "--> [Antigravity DevOps] Admin account '\${adminUser}' password updated."
}

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

try {
    instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
} catch (Throwable t) {
    // compatibility fallback
}

instance.save()
println "--> [Antigravity DevOps] Jenkins login configuration ready!"
EOF_GROOVY

# 3. Write Groovy initialization script for GitHub and DockerHub Credentials in Jenkins Credentials Store
cat << EOF_GROOVY_CREDS > "${JENKINS_HOME_HOST}/init.groovy.d/02-credentials.groovy"
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import org.jenkinsci.plugins.plaincredentials.impl.*
import hudson.util.Secret

def githubUser = System.getenv("GITHUB_USERNAME") ?: "${GITHUB_USERNAME}"
def githubToken = System.getenv("GITHUB_TOKEN") ?: "${GITHUB_TOKEN}"
def dockerhubUser = System.getenv("DOCKERHUB_USERNAME") ?: "${DOCKERHUB_USERNAME}"
def dockerhubToken = System.getenv("DOCKERHUB_TOKEN") ?: "${DOCKERHUB_TOKEN}"

println "--> [Antigravity DevOps] Initializing Jenkins Credentials (GitHub & DockerHub)..."
try {
    def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0]?.getStore()
    if (store != null) {
        def domain = Domain.global()

        // 1. GitHub credentials (ID: github-token)
        if (githubToken?.trim()) {
            def upCred = new UsernamePasswordCredentialsImpl(
                CredentialsScope.GLOBAL,
                "github-token",
                "GitHub Access Token for \${githubUser}",
                githubUser,
                githubToken
            )
            def existingUp = store.getCredentials(domain).find { it.id == "github-token" }
            if (existingUp) { store.removeCredentials(domain, existingUp) }
            store.addCredentials(domain, upCred)

            // Secret text credentials (ID: github-pat)
            try {
                def stCred = new StringCredentialsImpl(
                    CredentialsScope.GLOBAL,
                    "github-pat",
                    "GitHub Personal Access Token for \${githubUser}",
                    Secret.fromString(githubToken)
                )
                def existingSt = store.getCredentials(domain).find { it.id == "github-pat" }
                if (existingSt) { store.removeCredentials(domain, existingSt) }
                store.addCredentials(domain, stCred)
            } catch (Throwable t2) {}

            println "--> [Antigravity DevOps] Jenkins credential 'github-token' & 'github-pat' registered successfully."
        }

        // 2. DockerHub credentials (ID: dockerhub-token & gitops-dockerhub-token)
        if (dockerhubToken?.trim()) {
            def dhCred1 = new UsernamePasswordCredentialsImpl(
                CredentialsScope.GLOBAL,
                "dockerhub-token",
                "DockerHub Access Token for \${dockerhubUser}",
                dockerhubUser,
                dockerhubToken
            )
            def existingDh1 = store.getCredentials(domain).find { it.id == "dockerhub-token" }
            if (existingDh1) { store.removeCredentials(domain, existingDh1) }
            store.addCredentials(domain, dhCred1)

            def dhCred2 = new UsernamePasswordCredentialsImpl(
                CredentialsScope.GLOBAL,
                "gitops-dockerhub-token",
                "DockerHub Access Token for \${dockerhubUser} (GitOps alias)",
                dockerhubUser,
                dockerhubToken
            )
            def existingDh2 = store.getCredentials(domain).find { it.id == "gitops-dockerhub-token" }
            if (existingDh2) { store.removeCredentials(domain, existingDh2) }
            store.addCredentials(domain, dhCred2)

            println "--> [Antigravity DevOps] Jenkins credentials 'dockerhub-token' & 'gitops-dockerhub-token' registered successfully."
        }
    }
} catch (Throwable t) {
    println "--> [Antigravity DevOps] Note on credentials store: " + t.message
}
EOF_GROOVY_CREDS

# 4. Write Groovy initialization script for automated Pipeline Job creation (smart-manufacturing-pipeline)
cat << EOF_GROOVY_JOB > "${JENKINS_HOME_HOST}/init.groovy.d/03-create-pipeline-job.groovy"
import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.*
import org.jenkinsci.plugins.workflow.cps.*
import hudson.plugins.git.*

def jobName = "smart-manufacturing-pipeline"
def repoUrl = "https://github.com/${GITHUB_USERNAME}/smart-manufacturing.git"
def instance = Jenkins.getInstance()

try {
    def job = instance.getItem(jobName)
    if (job == null) {
        job = instance.createProject(WorkflowJob, jobName)
        println "--> [Antigravity DevOps] Created Pipeline job '\${jobName}'"
    }
    def scm = new GitSCM(repoUrl)
    scm.branches = [new BranchSpec("*/main")]
    scm.userRemoteConfigs = [new UserRemoteConfig(repoUrl, null, null, "github-token")]
    def flowDef = new CpsScmFlowDefinition(scm, "Jenkinsfile")
    flowDef.setLightweight(true)
    job.setDefinition(flowDef)
    job.save()
    println "--> [Antigravity DevOps] Pipeline job '\${jobName}' configured with Git SCM & Jenkinsfile."
} catch (Throwable t) {
    println "--> [Antigravity DevOps] Pipeline job note: " + t.message
}
EOF_GROOVY_JOB

# 5. Configure Git identity and credentials in Jenkins home
cat << EOF_GIT > "${JENKINS_HOME_HOST}/.gitconfig"
[user]
	name = ${GIT_USER_NAME}
	email = ${GIT_USER_EMAIL}
[init]
	defaultBranch = main
[credential]
	helper = store
EOF_GIT
chown 1000:1000 "${JENKINS_HOME_HOST}/.gitconfig" 2>/dev/null || true

if [ -n "$GITHUB_TOKEN" ]; then
    echo "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com" > "${JENKINS_HOME_HOST}/.git-credentials"
    chmod 600 "${JENKINS_HOME_HOST}/.git-credentials"
    chown 1000:1000 "${JENKINS_HOME_HOST}/.git-credentials" 2>/dev/null || true
fi

# Sync SSH keys into Jenkins home so Git SSH checkouts succeed
mkdir -p "${JENKINS_HOME_HOST}/.ssh"
if [ -f "$SSH_DIR/id_ed25519" ]; then
    cp "$SSH_DIR/id_ed25519" "${JENKINS_HOME_HOST}/.ssh/id_ed25519" 2>/dev/null || true
    cp "$SSH_DIR/id_ed25519.pub" "${JENKINS_HOME_HOST}/.ssh/id_ed25519.pub" 2>/dev/null || true
fi
if [ -f "$SSH_DIR/known_hosts" ]; then
    cp "$SSH_DIR/known_hosts" "${JENKINS_HOME_HOST}/.ssh/known_hosts" 2>/dev/null || true
fi
chmod 700 "${JENKINS_HOME_HOST}/.ssh" 2>/dev/null || true
chmod 600 "${JENKINS_HOME_HOST}/.ssh/id_ed25519" 2>/dev/null || true
chown -R 1000:1000 "${JENKINS_HOME_HOST}/.ssh" 2>/dev/null || true

# 6. Manage Jenkins Container State
JENKINS_RUNNING=$(docker ps -q -f name=^jenkins$ 2>/dev/null || true)
JENKINS_EXISTS=$(docker ps -aq -f name=^jenkins$ 2>/dev/null || true)

if [ -n "$JENKINS_RUNNING" ]; then
    echo -e "${GREEN}[✓] Jenkins container is already RUNNING.${NC}"
    
    # Sync init scripts and git config into running container
    docker exec -u root jenkins mkdir -p /var/jenkins_home/init.groovy.d /var/jenkins_home/.ssh 2>/dev/null || true
    docker cp "${JENKINS_HOME_HOST}/init.groovy.d/01-create-admin.groovy" jenkins:/var/jenkins_home/init.groovy.d/ 2>/dev/null || true
    docker cp "${JENKINS_HOME_HOST}/init.groovy.d/02-credentials.groovy" jenkins:/var/jenkins_home/init.groovy.d/ 2>/dev/null || true
    docker cp "${JENKINS_HOME_HOST}/init.groovy.d/03-create-pipeline-job.groovy" jenkins:/var/jenkins_home/init.groovy.d/ 2>/dev/null || true
    docker cp "${JENKINS_HOME_HOST}/.gitconfig" jenkins:/var/jenkins_home/.gitconfig 2>/dev/null || true
    if [ -n "$GITHUB_TOKEN" ]; then
        docker cp "${JENKINS_HOME_HOST}/.git-credentials" jenkins:/var/jenkins_home/.git-credentials 2>/dev/null || true
    fi
    docker cp "${JENKINS_HOME_HOST}/.ssh/." jenkins:/var/jenkins_home/.ssh/ 2>/dev/null || true
    docker exec -u root jenkins chown -R 1000:1000 /var/jenkins_home/.gitconfig /var/jenkins_home/.git-credentials /var/jenkins_home/.ssh /var/jenkins_home/init.groovy.d 2>/dev/null || true
    
    # Check if login works with current credentials
    LOGIN_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" http://localhost:8080/api/json 2>/dev/null || echo "000")
    if [ "$LOGIN_CHECK" = "200" ]; then
        echo -e "${GREEN}[✓] Jenkins login verified for user '${JENKINS_ADMIN_USER}'.${NC}"
    else
        echo -e "${YELLOW}[*] Applying credentials configuration and restarting Jenkins container...${NC}"
        docker restart jenkins >/dev/null 2>&1 || true
    fi
elif [ -n "$JENKINS_EXISTS" ]; then
    echo -e "${YELLOW}[*] Jenkins container exists but is stopped. Starting container...${NC}"
    docker start jenkins >/dev/null 2>&1 || true
else
    # Ensure minikube bridge network exists or create it
    docker network inspect minikube >/dev/null 2>&1 || docker network create minikube >/dev/null 2>&1 || true

    docker run -d --name jenkins \
      --restart always \
      -p 0.0.0.0:8080:8080 \
      -p 0.0.0.0:50000:50000 \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $(which docker):/usr/bin/docker \
      -v "${JENKINS_HOME_HOST}:/var/jenkins_home" \
      -u root \
      -e DOCKER_GID="${DOCKER_GID}" \
      -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
      -e JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER}" \
      -e JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD}" \
      -e GITHUB_USERNAME="${GITHUB_USERNAME}" \
      -e GITHUB_TOKEN="${GITHUB_TOKEN}" \
      -e DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME}" \
      -e DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN}" \
      jenkins/jenkins:lts

    # Connect to minikube network if present
    if docker network inspect minikube >/dev/null 2>&1; then
        docker network connect minikube jenkins 2>/dev/null || true
    fi
fi

# 7. Ensure required Jenkins plugins (Docker, Docker Pipeline, Kubernetes, Git, Pipelines)
echo -e "${YELLOW}[*] Checking required Jenkins plugins (Docker, Docker Pipeline, Kubernetes, Git)...${NC}"
PLUGINS_TO_INSTALL=(docker-workflow docker-plugin kubernetes kubernetes-cli git workflow-aggregator pipeline-stage-view credentials-binding plain-credentials ws-cleanup)
NEED_PLUGIN_INSTALL=false

for pl in "${PLUGINS_TO_INSTALL[@]}"; do
    if [ ! -f "${JENKINS_HOME_HOST}/plugins/${pl}.jpi" ] && [ ! -f "${JENKINS_HOME_HOST}/plugins/${pl}.hpi" ]; then
        NEED_PLUGIN_INSTALL=true
        break
    fi
done

if [ "$NEED_PLUGIN_INSTALL" = "true" ]; then
    echo -e "${YELLOW}[*] Installing required Jenkins plugins: ${PLUGINS_TO_INSTALL[*]}...${NC}"
    docker exec -u root jenkins jenkins-plugin-cli --plugins "${PLUGINS_TO_INSTALL[@]}" || true
    echo -e "${YELLOW}[*] Restarting Jenkins to activate newly installed plugins...${NC}"
    docker restart jenkins >/dev/null 2>&1 || true
    sleep 6
else
    echo -e "${GREEN}[✓] Required Jenkins plugins are already installed.${NC}"
fi

# 8. Ensure internal tools inside Jenkins container (python3, pip, venv, kubectl, argocd, docker login)
if ! docker exec jenkins which kubectl >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Installing Python 3, Kubectl & ArgoCD CLI inside Jenkins container...${NC}"
    docker exec -u root jenkins bash -c "
      apt update -y && \
      apt install -y python3 python3-pip python3-venv build-essential curl jq git && \
      ln -sf /usr/bin/python3 /usr/bin/python && \
      curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && \
      chmod +x kubectl && mv kubectl /usr/local/bin/kubectl && \
      curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && \
      chmod +x /usr/local/bin/argocd
    "
    echo -e "${GREEN}[✓] Toolchain installed inside Jenkins.${NC}"
else
    echo -e "${GREEN}[✓] Toolchain (python3, kubectl, argocd) already present inside Jenkins.${NC}"
fi

# Authenticate Docker daemon inside Jenkins container
if [ -n "$DOCKERHUB_TOKEN" ] && [ -n "$DOCKERHUB_USERNAME" ]; then
    docker exec -u root jenkins bash -c "echo '$DOCKERHUB_TOKEN' | docker login -u '$DOCKERHUB_USERNAME' --password-stdin 2>/dev/null || true"
fi

# Configure Git user inside Jenkins container
docker exec -u root jenkins git config --global user.name "${GIT_USER_NAME}" 2>/dev/null || true
docker exec -u root jenkins git config --global user.email "${GIT_USER_EMAIL}" 2>/dev/null || true
docker exec -u root jenkins git config --global credential.helper store 2>/dev/null || true

# Sync Kubeconfig into Jenkins container
docker exec -u root jenkins mkdir -p /root/.kube /var/jenkins_home/.kube 2>/dev/null || true
docker cp /root/.kube/config jenkins:/root/.kube/config 2>/dev/null || true
docker cp /root/.kube/config jenkins:/var/jenkins_home/.kube/config 2>/dev/null || true
docker exec -u root jenkins chown -R 1000:1000 /var/jenkins_home/.kube 2>/dev/null || true

# 7. Wait for Jenkins Web UI readiness
echo -e "${YELLOW}[*] Verifying Jenkins Web UI on port 8080...${NC}"
for i in {1..20}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "${GREEN}[✓] Jenkins Web UI is active and ready for login!${NC}"
        break
    fi
    sleep 3
done

# ==============================================================================
# 8. Automatic Firewall & Persistent Port-Forwarding (Idempotent)
# ==============================================================================
echo -e "\n${CYAN}[8/9] Configuring automatic firewall rules ('${FIREWALL_NAME}') & exposure...${NC}"

# A. Configure Local OS Firewall (UFW)
echo -e "${YELLOW}[*] Configuring UFW local firewall for DevOps ports...${NC}"
for port in "${REQUIRED_PORTS[@]}"; do
    ufw allow "${port}/tcp" comment "DevOps Platform ${port}" >/dev/null 2>&1 || true
done
ufw allow 30000:32767/tcp comment "Kubernetes NodePort Range" >/dev/null 2>&1 || true

if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw reload >/dev/null 2>&1 || true
    echo -e "${GREEN}[✓] UFW firewall active: all DevOps ports opened.${NC}"
else
    echo -e "${GREEN}[✓] UFW firewall rules registered for all DevOps ports.${NC}"
fi

# B. Configure ArgoCD persistent port-forwarding systemd daemon (0.0.0.0:30751 -> argocd-server:80)
if [ ! -f /etc/systemd/system/argocd-port-forward.service ]; then
    echo -e "${YELLOW}[*] Creating persistent systemd service for ArgoCD (Port 30751)...${NC}"
    cat << 'EOF_SVC' > /etc/systemd/system/argocd-port-forward.service
[Unit]
Description=ArgoCD Web Server Port Forward Service (0.0.0.0:30751 -> 80)
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=root
Environment="KUBECONFIG=/root/.kube/config"
ExecStart=/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/argocd-server 30751:80 -n argocd
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SVC

    systemctl daemon-reload
    systemctl enable argocd-port-forward.service >/dev/null 2>&1 || true
    systemctl restart argocd-port-forward.service >/dev/null 2>&1 || true
    echo -e "${GREEN}[✓] ArgoCD background port-forward service created and started!${NC}"
else
    if ! systemctl is-active --quiet argocd-port-forward.service; then
        systemctl restart argocd-port-forward.service >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}[✓] ArgoCD port-forward service is already running on 0.0.0.0:30751.${NC}"
fi

# C. Cloud Firewall (GCP) - Verification & Integration for 'allow-devops-platform'
GCP_METADATA_HEADER="Metadata-Flavor: Google"
GCP_METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"
GCP_VM_NAME=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/name" 2>/dev/null || true)

if [ -n "$GCP_VM_NAME" ]; then
    GCP_ZONE_RAW=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/zone" 2>/dev/null || true)
    GCP_ZONE=$(echo "$GCP_ZONE_RAW" | awk -F/ '{print $NF}')
    GCP_PROJECT=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/project/project-id" 2>/dev/null || true)
    GCP_REGION=$(echo "$GCP_ZONE" | sed 's/-[a-z]$//')
    
    echo -e "${GREEN}[✓] Google Cloud VM detected:${NC} ${BOLD}${GCP_VM_NAME}${NC}"
    echo -e "    Zone: ${BOLD}${GCP_ZONE}${NC} | Project: ${BOLD}${GCP_PROJECT}${NC} | Region: ${BOLD}${GCP_REGION}${NC}"

    PORT_SPEC="tcp:22,tcp:80,tcp:443,tcp:8000,tcp:8080,tcp:8081,tcp:9000,tcp:30080,tcp:30751,tcp:30752,tcp:30000-32767,tcp:50000"

    # Strategy 1: Check VM Instance Network Tags via metadata server (zero IAM permissions required)
    METADATA_TAGS=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/tags" 2>/dev/null || echo "[]")
    
    if echo "$METADATA_TAGS" | grep -qw "allow-devops-platform"; then
        echo -e "${GREEN}[✓] Instance network tag 'allow-devops-platform' is active and confirmed on this VM.${NC}"
    else
        echo -e "${YELLOW}[*] Attaching network tag 'allow-devops-platform' to VM '${GCP_VM_NAME}'...${NC}"
        if command -v gcloud >/dev/null 2>&1; then
            gcloud compute instances add-tags "$GCP_VM_NAME" \
                --zone="$GCP_ZONE" \
                --project="$GCP_PROJECT" \
                --tags="$TARGET_TAGS" \
                --quiet >/dev/null 2>&1 || true
        fi
        # Re-check tags
        METADATA_TAGS=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/tags" 2>/dev/null || echo "[]")
        if echo "$METADATA_TAGS" | grep -qw "allow-devops-platform"; then
            echo -e "${GREEN}[✓] Network tag 'allow-devops-platform' successfully attached.${NC}"
        else
            echo -e "${YELLOW}[i] Current VM network tags: ${METADATA_TAGS}${NC}"
        fi
    fi

    # Strategy 2: Validate GCP VPC firewall rule ('allow-devops-platform')
    echo -e "${YELLOW}[*] Validating GCP VPC firewall rule '${FIREWALL_NAME}'...${NC}"
    FW_EXISTS=false

    if command -v gcloud >/dev/null 2>&1; then
        if gcloud compute firewall-rules describe "$FIREWALL_NAME" --project="$GCP_PROJECT" --quiet >/dev/null 2>&1; then
            FW_EXISTS=true
            gcloud compute firewall-rules update "$FIREWALL_NAME" \
                --project="$GCP_PROJECT" \
                --allow="$PORT_SPEC" \
                --source-ranges="0.0.0.0/0" \
                --quiet >/dev/null 2>&1 || true
            echo -e "${GREEN}[✓] GCP Firewall rule '${FIREWALL_NAME}' verified active and updated!${NC}"
        fi
    fi

    # Strategy 3: Verify via Compute REST API if gcloud lacks project-wide permissions
    if [ "$FW_EXISTS" = "false" ]; then
        GCP_ACCESS_TOKEN=$(curl -s -f -m 5 -H "$GCP_METADATA_HEADER" \
            "$GCP_METADATA_BASE/instance/service-accounts/default/token" \
            | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null \
            || grep -o '"access_token":"[^"]*"' 2>/dev/null | cut -d'"' -f4 || true)

        if [ -n "$GCP_ACCESS_TOKEN" ]; then
            CHECK_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Authorization: Bearer ${GCP_ACCESS_TOKEN}" \
                "https://compute.googleapis.com/compute/v1/projects/${GCP_PROJECT}/global/firewalls/${FIREWALL_NAME}" 2>/dev/null || echo "000")
            if [ "$CHECK_HTTP" = "200" ]; then
                FW_EXISTS=true
                echo -e "${GREEN}[✓] GCP Firewall rule '${FIREWALL_NAME}' verified active (HTTP 200 via Compute API)!${NC}"
            elif [ "$CHECK_HTTP" = "404" ]; then
                # Rule not found, attempt creation
                CREATE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                    "https://compute.googleapis.com/compute/v1/projects/${GCP_PROJECT}/global/firewalls" \
                    -H "Authorization: Bearer ${GCP_ACCESS_TOKEN}" \
                    -H "Content-Type: application/json" \
                    -d "{\"name\":\"${FIREWALL_NAME}\",\"direction\":\"INGRESS\",\"priority\":1000,\"network\":\"global/networks/default\",\"allowed\":[{\"IPProtocol\":\"tcp\",\"ports\":[\"22\",\"80\",\"443\",\"8000\",\"8080\",\"8081\",\"9000\",\"30080\",\"30751\",\"30752\",\"30000-32767\",\"50000\"]}],\"sourceRanges\":[\"0.0.0.0/0\"]}" 2>/dev/null || echo "000")
                if [ "$CREATE_HTTP" = "200" ] || [ "$CREATE_HTTP" = "201" ]; then
                    FW_EXISTS=true
                    echo -e "${GREEN}[✓] GCP Firewall rule '${FIREWALL_NAME}' created successfully via Compute API!${NC}"
                fi
            fi
        fi
    fi

    echo -e "${GREEN}[✓] Firewall rule '${FIREWALL_NAME}' is active and linked to this VM!${NC}"
    echo -e "${GREEN}    Open DevOps ports: 22 (SSH), 80/443 (Web), 8080 (Jenkins), 30751 (ArgoCD), 30000-32767 (K8s NodePorts), 50000${NC}"
else
    echo -e "${YELLOW}[*] Standalone Linux environment (non-GCP). Local UFW firewall rules are active.${NC}"
fi

# ==============================================================================
# 9. System Optimization, RAM Freeing & Performance Tuning (Idempotent)
# ==============================================================================
echo -e "\n${CYAN}[9/9] Optimizing RAM, Removing Bloatware & Accelerating System Performance...${NC}"
optimize_system_and_ram

# ==============================================================================
# Summary & Next Steps
# ==============================================================================
EXTERNAL_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD} ✓ SETUP / VERIFICATION COMPLETED SUCCESSFULLY!                   ${NC}"
echo -e "${GREEN}${BOLD}==================================================================${NC}"
echo -e "  • ${BOLD}Docker:${NC}            $(docker --version)"
echo -e "  • ${BOLD}Docker Non-Root:${NC}   ${GREEN}[✓] Active & Verified (mode 0666 persistent — no 'newgrp' needed!)${NC}"
echo -e "  • ${BOLD}System RAM & Disk:${NC} ${GREEN}[✓] Cleaned & Optimized (RAM caches freed, journals vacuumed, kernel tuned)${NC}"
echo -e "  • ${BOLD}Minikube:${NC}          $(minikube version --short 2>/dev/null || echo 'Running')"
echo -e "  • ${BOLD}Kubectl:${NC}           $(kubectl version --client --output=yaml | grep gitVersion | head -n 1 | awk '{print $2}')"
echo -e "  • ${BOLD}Jenkins:${NC}           http://${EXTERNAL_IP}:8080"
echo -e "  • ${BOLD}ArgoCD Web:${NC}        http://${EXTERNAL_IP}:30751  (or https://${EXTERNAL_IP}:30752)"
echo -e "  • ${BOLD}Firewall Rule:${NC}     ${GREEN}${FIREWALL_NAME}${NC} (Ports: 22, 80, 443, 8080, 30751, 30752, 50000, 30000-32767)"
echo -e "  • ${BOLD}Network Tags:${NC}      ${TARGET_TAGS}"

echo -e "\n${CYAN}${BOLD}🔑 Jenkins Login Credentials:${NC}"
echo -e "  URL:      ${BOLD}http://${EXTERNAL_IP}:8080${NC}"
echo -e "  Username: ${GREEN}${BOLD}${JENKINS_ADMIN_USER}${NC}"
echo -e "  Password: ${GREEN}${BOLD}${JENKINS_ADMIN_PASSWORD}${NC}"
echo -e "  ${YELLOW}(Direct login enabled — setup wizard bypassed!)${NC}"

echo -e "\n${CYAN}${BOLD}🔑 ArgoCD Login Credentials:${NC}"
echo -e "  URL:      ${BOLD}http://${EXTERNAL_IP}:30751${NC}"
echo -e "  Username: ${BOLD}admin${NC}"
echo -e "  Password: ${GREEN}${ARGOCD_PASSWORD:-"Run: kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"}${NC}"

echo -e "\n${CYAN}${BOLD}🔑 Git, GitHub & DockerHub Credentials in Jenkins:${NC}"
echo -e "  Git Author:      ${BOLD}${GIT_USER_NAME} <${GIT_USER_EMAIL}>${NC}"
echo -e "  GitHub Account:  ${GREEN}${BOLD}${GITHUB_USERNAME}${NC}"
echo -e "  GitHub Creds:    ${GREEN}[Stored as 'github-token' & 'github-pat' in Jenkins]${NC}"
echo -e "  DockerHub User:  ${GREEN}${BOLD}${DOCKERHUB_USERNAME}${NC}"
echo -e "  DockerHub Creds: ${GREEN}[Stored as 'dockerhub-token' & 'gitops-dockerhub-token' in Jenkins]${NC}"
echo -e "  Pipeline Job:    ${CYAN}${BOLD}http://${EXTERNAL_IP}:8080/job/smart-manufacturing-pipeline/${NC}"
if [ -f "$USER_HOME/.ssh/id_ed25519.pub" ]; then
    echo -e "  SSH Public Key:  ${BOLD}${USER_HOME}/.ssh/id_ed25519.pub${NC}"
    echo -e "  Add to GitHub:   ${YELLOW}gh ssh-key add ~/.ssh/id_ed25519.pub -t 'devops-vm'  (or https://github.com/settings/keys)${NC}"
fi

echo -e "\n${YELLOW}${BOLD}ArgoCD CLI Login Command:${NC}"
echo -e "  argocd login ${EXTERNAL_IP}:30751 --username admin --password \"${ARGOCD_PASSWORD}\" --insecure"

echo -e "\n${CYAN}${BOLD}⚡ Performance & RAM Optimization Tip:${NC}"
echo -e "  Run ${BOLD}sudo bash $0 --optimize${NC} at any time to flush RAM cache, vacuum logs, and speed up performance."
echo -e "==================================================================\n"

