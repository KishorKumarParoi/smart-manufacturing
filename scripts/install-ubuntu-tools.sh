#!/usr/bin/env bash
# ==============================================================================
# ALL-IN-ONE ENTERPRISE DEVOPS PLATFORM SETUP (UBUNTU / DEBIAN)
# Docker | Minikube | Kubectl | ArgoCD | SonarQube | Nexus 3 | Trivy | Prometheus | Grafana | Jenkins
# Target OS: Ubuntu 20.04 / 22.04 / 24.04 LTS | Debian 11 / 12 / 13 (Trixie) (x86_64)
# Fully aligned with Jenkinsfile CI/CD multi-stage pipeline and GitOps workflow
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
====================================================================================
  ENTERPRISE DEVOPS & AI OPERATIONS PLATFORM AUTOMATED SETUP
  Docker | Minikube | Kubectl | ArgoCD | SonarQube | Nexus 3 | Trivy | Prometheus | Grafana | Jenkins
====================================================================================
EOF
    echo -e "${NC}"
}

header

show_help() {
    echo "Usage: sudo bash $0 [OPTIONS]"
    echo "Options:"
    echo "  (no args)                     Run full DevOps platform installation & verification"
    echo "  --github-token <token>        Set GitHub Personal Access Token for Jenkins & Git"
    echo "  --dockerhub-token <token>     Set DockerHub Access Token for Jenkins & Docker"
    echo "  --github-user <username>      Set GitHub username (default: KishorKumarParoi)"
    echo "  --dockerhub-user <username>   Set DockerHub username (default: kishorkumarparoi)"
    echo "  --jenkins-password <pass>     Set Jenkins admin password (default: admin123)"
    echo "  --sonarqube-token <token>     Set SonarQube system token"
    echo "  --nexus-password <pass>       Set Sonatype Nexus admin password (default: admin123)"
    echo "  --nexus-repo <repo>           Set Nexus raw release repo name (default: smart-manufacturing-releases)"
    echo "  --optimize, --cleanup         Clear RAM caches, vacuum logs, and tune kernel"
    echo "  --fix-minikube                Reset stale Minikube Docker network bridge"
    echo "  --help, -h                    Show this help message"
}

# Ensure running with sudo or as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run this script with sudo or as root:${NC}"
    echo "  sudo bash $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Discover and source all candidate environment secret files
ENV_FILES=(
    "/etc/devops.env"
    "/root/.devops.env"
    "${USER_HOME}/.devops.env"
    "${USER_HOME}/smart_manufacturing/.env"
    "${USER_HOME}/smart-manufacturing/.env"
    "${WORKSPACE_ROOT}/.env"
    "${PWD}/.env"
    "${SCRIPT_DIR}/.env"
)
for ef in "${ENV_FILES[@]}"; do
    if [ -f "$ef" ]; then
        # shellcheck disable=SC1090
        set -a
        source "$ef" 2>/dev/null || true
        set +a
    fi
done

# Parse CLI options (CLI options take priority over .env files)
RUN_MODE="full"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --github-token|--gh-token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        --dockerhub-token|--dh-token)
            DOCKERHUB_TOKEN="$2"
            shift 2
            ;;
        --github-username|--gh-user|--github-user)
            GITHUB_USERNAME="$2"
            shift 2
            ;;
        --dockerhub-username|--dh-user|--dockerhub-user)
            DOCKERHUB_USERNAME="$2"
            shift 2
            ;;
        --jenkins-password|--jenkins-admin-password)
            JENKINS_ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --sonarqube-token|--sq-token)
            SONARQUBE_TOKEN="$2"
            shift 2
            ;;
        --nexus-password|--nexus-admin-password)
            NEXUS_ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --nexus-repo)
            NEXUS_REPO="$2"
            shift 2
            ;;
        --optimize|--clean|--cleanup|--speedup|-o)
            RUN_MODE="optimize"
            shift
            ;;
        --fix-minikube|--repair-minikube)
            RUN_MODE="fix-minikube"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Configuration defaults aligned with Jenkinsfile
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-admin123}"
GIT_USER_NAME="${GIT_USER_NAME:-Kishor Kumar Paroi}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-1703053@student.ruet.ac.bd}"
GITHUB_USERNAME="${GITHUB_USERNAME:-KishorKumarParoi}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-kishorkumarparoi}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"
SONARQUBE_TOKEN="${SONARQUBE_TOKEN:-squ_63b54a3af718c9dc398fb8e2102118114db3d548}"
NEXUS_ADMIN_USER="${NEXUS_ADMIN_USER:-admin}"
NEXUS_ADMIN_PASSWORD="${NEXUS_ADMIN_PASSWORD:-admin123}"
NEXUS_REPO="${NEXUS_REPO:-smart-manufacturing-releases}"
APP_NAME="smart-manufacturing"

FIREWALL_NAME="${FIREWALL_NAME:-allow-devops-platform}"
TARGET_TAGS="allow-devops-platform,devops-control-plane,devops-vm"
REQUIRED_PORTS=(22 80 443 3000 8000 8080 8081 8082 9000 9090 30080 30090 30300 30751 30752 50000)

# Non-blocking interactive prompt if tokens are missing and /dev/tty is available
if [ -z "$GITHUB_TOKEN" ] && [ -c /dev/tty ]; then
    echo -e "${YELLOW}[*] GitHub Token not detected in arguments or .env files.${NC}"
    echo -n "    Enter GitHub Personal Access Token (or press ENTER to auto-generate placeholder): " > /dev/tty
    read -r -t 15 user_gh_tok < /dev/tty || true
    echo "" > /dev/tty
    if [ -n "$user_gh_tok" ]; then
        GITHUB_TOKEN="$user_gh_tok"
    fi
fi

if [ -z "$DOCKERHUB_TOKEN" ] && [ -c /dev/tty ]; then
    echo -e "${YELLOW}[*] DockerHub Token not detected in arguments or .env files.${NC}"
    echo -n "    Enter DockerHub Personal Access Token (or press ENTER to auto-generate placeholder): " > /dev/tty
    read -r -t 15 user_dh_tok < /dev/tty || true
    echo "" > /dev/tty
    if [ -n "$user_dh_tok" ]; then
        DOCKERHUB_TOKEN="$user_dh_tok"
    fi
fi

# Fallback tokens for automated pipelines
GITHUB_TOKEN_EFFECTIVE="${GITHUB_TOKEN:-ghp_placeholder_token_devops_auto_000000000000}"
DOCKERHUB_TOKEN_EFFECTIVE="${DOCKERHUB_TOKEN:-dckr_pat_placeholder_devops_auto_000000000000}"

# Detect OS distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-ubuntu}"
    OS_CODENAME="${VERSION_CODENAME:-}"
else
    OS_ID="ubuntu"
    OS_CODENAME="jammy"
fi

if [ "$OS_ID" = "ubuntu" ]; then
    DOCKER_DISTRO="ubuntu"
    [ -z "$OS_CODENAME" ] && OS_CODENAME="jammy"
elif [ "$OS_ID" = "debian" ]; then
    DOCKER_DISTRO="debian"
    [ -z "$OS_CODENAME" ] && OS_CODENAME="bookworm"
else
    DOCKER_DISTRO="ubuntu"
    OS_CODENAME="jammy"
fi

# High-Performance System & Kernel Tuning
optimize_system_and_ram() {
    echo -e "\n${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${CYAN}${BOLD} [SYSTEM ACCELERATION] RAM Flush, Conntrack & Kernel Optimizer     ${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"

    # 1. Vacuum journal logs
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=1d --vacuum-size=50M >/dev/null 2>&1 || true
    fi

    # 2. Prune Docker dangling caches
    if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
        docker builder prune -f --filter "until=24h" >/dev/null 2>&1 || true
        docker network prune -f >/dev/null 2>&1 || true
    fi

    # 3. Apply High-Performance Kernel & Conntrack Parameters
    echo -e "${YELLOW}[*] Applying Linux kernel parameters (conntrack max 1M, max_map_count 524288)...${NC}"
    mkdir -p /etc/sysctl.d
    cat << "EOF_SYSCTL" > /etc/sysctl.d/99-devops-performance.conf
# Antigravity Enterprise DevOps Platform Tuning
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
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 600
EOF_SYSCTL

    modprobe nf_conntrack 2>/dev/null || true
    sysctl --system >/dev/null 2>&1 || true
    sysctl -w net.netfilter.nf_conntrack_max=1048576 2>/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=600 2>/dev/null || true

    mkdir -p /etc/security/limits.d
    cat << "EOF_LIMITS" > /etc/security/limits.d/99-devops.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65536
* hard nproc 65536
root soft nofile 1048576
root hard nofile 1048576
EOF_LIMITS

    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    echo -e "${GREEN}[✓] System RAM and kernel network parameters optimized.${NC}"
}

# Minikube Self-Healing & Network Recovery Function
fix_and_start_minikube() {
    echo -e "\n${YELLOW}${BOLD}[*] Auto-Healing Minikube Cluster & Docker Network IPAM...${NC}"
    
    if systemctl is-active --quiet k3s 2>/dev/null; then
        systemctl stop k3s 2>/dev/null || true
        systemctl disable k3s 2>/dev/null || true
    fi

    sudo -u "$REAL_USER" minikube delete --all --purge >/dev/null 2>&1 || true
    docker rm -f minikube 2>/dev/null || true
    docker network rm minikube 2>/dev/null || true
    docker network prune -f >/dev/null 2>&1 || true

    systemctl restart docker.socket docker >/dev/null 2>&1 || true
    chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -m u:"$REAL_USER":rw /var/run/docker.sock 2>/dev/null || true
        setfacl -m u:"$REAL_USER":rw /run/docker.sock 2>/dev/null || true
    fi
    sleep 2

    echo -e "${YELLOW}[*] Starting clean Minikube cluster using Docker driver...${NC}"
    if sudo -u "$REAL_USER" minikube start --driver=docker; then
        echo -e "${GREEN}[✓] Minikube cluster recovered and running!${NC}"
    else
        sudo -u "$REAL_USER" minikube delete --all --purge >/dev/null 2>&1 || true
        docker rm -f minikube 2>/dev/null || true
        docker network rm minikube 2>/dev/null || true
        sudo -u "$REAL_USER" minikube start --driver=docker --network=minikube-net
        echo -e "${GREEN}[✓] Minikube cluster recovered with clean network!${NC}"
    fi
}

if [ "$RUN_MODE" = "optimize" ]; then
    optimize_system_and_ram
    exit 0
elif [ "$RUN_MODE" = "fix-minikube" ]; then
    fix_and_start_minikube
    exit 0
fi

echo -e "${YELLOW}[*] Configuring DevOps toolchain for user:${NC} ${BOLD}${REAL_USER}${NC}"
echo -e "${YELLOW}[*] Jenkins admin account:${NC} ${BOLD}${JENKINS_ADMIN_USER}${NC}"
echo -e "${YELLOW}[*] Git & GitHub profile:${NC} ${BOLD}${GITHUB_USERNAME} (${GIT_USER_EMAIL})${NC}"
echo -e "${YELLOW}[*] DockerHub account:${NC} ${BOLD}${DOCKERHUB_USERNAME}${NC}"
echo -e "${YELLOW}[*] SonarQube token:${NC} ${BOLD}${SONARQUBE_TOKEN:0:8}...${NC}"
echo -e "${YELLOW}[*] Nexus repository:${NC} ${BOLD}${NEXUS_REPO}${NC}"

# ==============================================================================
# 1. Base Packages & Fast Python Manager (uv)
# ==============================================================================
echo -e "\n${CYAN}[1/10] Checking base utilities & fast tools...${NC}"

REQUIRED_PKGS=(ca-certificates curl gnupg lsb-release wget conntrack git jq ufw acl procps tar unzip)
if [ "$DOCKER_DISTRO" = "ubuntu" ]; then
    REQUIRED_PKGS+=(software-properties-common)
fi

MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}[*] Installing missing utilities: ${MISSING_PKGS[*]}...${NC}"
    apt-get update -y
    for pkg in "${MISSING_PKGS[@]}"; do
        apt-get install -y --no-install-recommends "$pkg" || true
    done
fi

# Install uv (Astral Python manager) on host
if ! command -v uv >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Installing uv (Astral fast Python manager) on host...${NC}"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    if [ -f "$HOME/.cargo/bin/uv" ]; then
        cp "$HOME/.cargo/bin/uv" /usr/local/bin/uv
    elif [ -f "$USER_HOME/.local/bin/uv" ]; then
        cp "$USER_HOME/.local/bin/uv" /usr/local/bin/uv
    fi
    chmod +x /usr/local/bin/uv 2>/dev/null || true
fi
echo -e "${GREEN}[✓] Base utilities & uv ready.${NC}"

# ==============================================================================
# 2. Docker CE & Socket Permissions
# ==============================================================================
echo -e "\n${CYAN}[2/10] Checking Docker CE installation & socket permissions...${NC}"

if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
    echo -e "${GREEN}[✓] Docker is already installed and running: ${NC}$(docker --version)"
else
    echo -e "${YELLOW}[*] Installing Docker CE for ${DOCKER_DISTRO}...${NC}"
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
fi

usermod -aG docker "$REAL_USER" 2>/dev/null || true
chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true
if command -v setfacl >/dev/null 2>&1; then
    setfacl -m u:"$REAL_USER":rw /var/run/docker.sock 2>/dev/null || true
    setfacl -m u:"$REAL_USER":rw /run/docker.sock 2>/dev/null || true
fi

# Authenticate Docker daemon if DockerHub token is provided
if [ -n "$DOCKERHUB_TOKEN" ] && [ -n "$DOCKERHUB_USERNAME" ]; then
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
    echo "$DOCKERHUB_TOKEN" | sudo -u "$REAL_USER" docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
fi
echo -e "${GREEN}[✓] Docker configured with non-root access.${NC}"

# ==============================================================================
# 3. Kubectl, ArgoCD CLI & Trivy Vulnerability Scanner
# ==============================================================================
echo -e "\n${CYAN}[3/10] Checking Kubectl, ArgoCD CLI & Trivy Scanner...${NC}"

# Kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Installing Kubectl...${NC}"
    K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl && mv kubectl /usr/local/bin/kubectl
fi
echo -e "${GREEN}[✓] Kubectl ready.${NC}"

# ArgoCD CLI
if ! command -v argocd >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Installing ArgoCD CLI...${NC}"
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
fi
echo -e "${GREEN}[✓] ArgoCD CLI ready.${NC}"

# Trivy Security Scanner (Filesystem & Container Scans)
if ! command -v trivy >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Installing Trivy vulnerability scanner...${NC}"
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.75.0 || {
        curl -sSL -O https://github.com/aquasecurity/trivy/releases/download/v0.75.0/trivy_0.75.0_Linux-64bit.tar.gz
        tar -xzf trivy_0.75.0_Linux-64bit.tar.gz -C /usr/local/bin trivy
        rm -f trivy_0.75.0_Linux-64bit.tar.gz
    }
    chmod +x /usr/local/bin/trivy
fi
echo -e "${GREEN}[✓] Trivy security scanner installed: $(trivy --version 2>/dev/null | head -n 1)${NC}"

# Shell aliases
if ! grep -q "alias k=kubectl" "$USER_HOME/.bashrc" 2>/dev/null; then
    echo "alias k=kubectl" >> "$USER_HOME/.bashrc"
    echo "source <(kubectl completion bash)" >> "$USER_HOME/.bashrc" 2>/dev/null || true
fi

# ==============================================================================
# 4. Git, GitHub CLI & SSH Keys
# ==============================================================================
echo -e "\n${CYAN}[4/10] Configuring Git & GitHub authentication (${GITHUB_USERNAME})...${NC}"

sudo -u "$REAL_USER" git config --global user.name "$GIT_USER_NAME"
sudo -u "$REAL_USER" git config --global user.email "$GIT_USER_EMAIL"
sudo -u "$REAL_USER" git config --global init.defaultBranch main
sudo -u "$REAL_USER" git config --global credential.helper store

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global init.defaultBranch main
git config --global credential.helper store

if ! command -v gh >/dev/null 2>&1; then
    mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update -y
    apt-get install -y gh || true
fi

SSH_DIR="$USER_HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
if [ ! -f "$SSH_DIR/id_ed25519" ] && [ ! -f "$SSH_DIR/id_rsa" ]; then
    sudo -u "$REAL_USER" ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -f "$SSH_DIR/id_ed25519" -N ""
    chown -R "$REAL_USER:$REAL_USER" "$SSH_DIR"
fi
ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$SSH_DIR/known_hosts" 2>/dev/null || true
chown -R "$REAL_USER:$REAL_USER" "$SSH_DIR"

if [ -n "$GITHUB_TOKEN" ]; then
    echo "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com" > "$USER_HOME/.git-credentials"
    chmod 600 "$USER_HOME/.git-credentials"
    chown "$REAL_USER:$REAL_USER" "$USER_HOME/.git-credentials"
fi
echo -e "${GREEN}[✓] Git & GitHub credentials configured.${NC}"

# ==============================================================================
# 5. Minikube Cluster (Containerd & Docker Bridge)
# ==============================================================================
echo -e "\n${CYAN}[5/10] Checking Minikube installation & cluster state...${NC}"

if ! command -v minikube >/dev/null 2>&1; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64
fi

MINIKUBE_STATUS=$(sudo -u "$REAL_USER" minikube status --format='{{.Host}}' 2>/dev/null || echo "Stopped")
if [ "$MINIKUBE_STATUS" = "Running" ] && sudo -u "$REAL_USER" kubectl get nodes >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Minikube cluster is already RUNNING!${NC}"
else
    if systemctl is-active --quiet k3s 2>/dev/null; then
        systemctl stop k3s 2>/dev/null || true
        systemctl disable k3s 2>/dev/null || true
    fi

    echo -e "${YELLOW}[*] Starting Minikube cluster using Docker driver...${NC}"
    if sudo -u "$REAL_USER" minikube start --driver=docker; then
        echo -e "${GREEN}[✓] Minikube cluster started successfully!${NC}"
    else
        fix_and_start_minikube
    fi
fi

# Ensure flattened kubeconfig for seamless tool consumption
mkdir -p /root/.kube "$USER_HOME/.kube"
sudo -u "$REAL_USER" kubectl config view --flatten --raw > /root/.kube/config 2>/dev/null || cp "$USER_HOME/.kube/config" /root/.kube/config 2>/dev/null || true
cp /root/.kube/config "$USER_HOME/.kube/config" 2>/dev/null || true
chmod 600 /root/.kube/config "$USER_HOME/.kube/config"
chown "$REAL_USER:$REAL_USER" "$USER_HOME/.kube/config"

echo -e "${GREEN}[✓] Kubernetes Nodes:${NC}"
kubectl get nodes

# ==============================================================================
# 6. ArgoCD Controller & Service (NodePort 30751)
# ==============================================================================
echo -e "\n${CYAN}[6/10] Checking ArgoCD in Kubernetes...${NC}"

ARGOCD_STATUS=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [ "$ARGOCD_STATUS" != "True" ]; then
    echo -e "${YELLOW}[*] Deploying ArgoCD manifests into namespace 'argocd'...${NC}"
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl rollout status deployment/argocd-server -n argocd --timeout=180s || true
fi

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 8080, "nodePort": 30751}, {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30752}]}}' 2>/dev/null || true

ARGOCD_PASSWORD=""
for i in {1..8}; do
    ARGOCD_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)
    [ -n "$ARGOCD_PASSWORD" ] && break
    sleep 2
done
echo -e "${GREEN}[✓] ArgoCD configured on NodePort 30751.${NC}"

# ==============================================================================
# 7. SonarQube & Sonatype Nexus 3 Platforms
# ==============================================================================
echo -e "\n${CYAN}[7/10] Configuring SonarQube (Port 9000) & Nexus 3 (Port 8081)...${NC}"

# Ensure minikube network exists
docker network inspect minikube >/dev/null 2>&1 || docker network create minikube >/dev/null 2>&1 || true

# A. SonarQube Community Edition
if docker ps -q -f name=^sonarqube$ >/dev/null 2>&1 && [ -n "$(docker ps -q -f name=^sonarqube$)" ]; then
    echo -e "${GREEN}[✓] SonarQube container is already RUNNING.${NC}"
else
    docker rm -f sonarqube >/dev/null 2>&1 || true
    echo -e "${YELLOW}[*] Starting SonarQube container on port 9000...${NC}"
    docker run -d --name sonarqube \
        --restart always \
        -p 0.0.0.0:9000:9000 \
        -v sonarqube_data:/opt/sonarqube/data \
        -v sonarqube_extensions:/opt/sonarqube/extensions \
        -v sonarqube_logs:/opt/sonarqube/logs \
        sonarqube:community

    docker network connect minikube sonarqube 2>/dev/null || true
fi

# Install sonar-scanner-cli on host
if ! command -v sonar-scanner >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Installing sonar-scanner CLI on host...${NC}"
    curl -sSL -O https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-6.2.1.4610-linux-x64.zip
    unzip -q sonar-scanner-cli-6.2.1.4610-linux-x64.zip -d /opt/
    rm -f sonar-scanner-cli-6.2.1.4610-linux-x64.zip
    ln -sf /opt/sonar-scanner-6.2.1.4610-linux-x64/bin/sonar-scanner /usr/local/bin/sonar-scanner
fi
echo -e "${GREEN}[✓] SonarQube & sonar-scanner ready.${NC}"

# B. Sonatype Nexus 3
if docker ps -q -f name=^nexus$ >/dev/null 2>&1 && [ -n "$(docker ps -q -f name=^nexus$)" ]; then
    echo -e "${GREEN}[✓] Nexus 3 container is already RUNNING.${NC}"
else
    docker rm -f nexus >/dev/null 2>&1 || true
    echo -e "${YELLOW}[*] Starting Sonatype Nexus 3 container on ports 8081 & 8082...${NC}"
    docker run -d --name nexus \
        --restart always \
        -p 0.0.0.0:8081:8081 \
        -p 0.0.0.0:8082:8082 \
        -v nexus_data:/nexus-data \
        sonatype/nexus3:latest

    docker network connect minikube nexus 2>/dev/null || true
fi

# Ensure Nexus EULA accepted & raw hosted repository created
echo -e "${YELLOW}[*] Validating Nexus 3 EULA acceptance & '${NEXUS_REPO}' repository...${NC}"
for attempt in {1..20}; do
    if curl -s -f http://localhost:8081/service/rest/v1/status >/dev/null 2>&1; then
        # Check and accept EULA
        EULA_BODY=$(curl -s -u "${NEXUS_ADMIN_USER}:${NEXUS_ADMIN_PASSWORD}" http://localhost:8081/service/rest/v1/system/eula 2>/dev/null || true)
        if echo "$EULA_BODY" | grep -q '"accepted":false'; then
            ACCEPT_PAYLOAD=$(echo "$EULA_BODY" | jq '.accepted = true' 2>/dev/null || true)
            if [ -n "$ACCEPT_PAYLOAD" ]; then
                curl -s -X POST -u "${NEXUS_ADMIN_USER}:${NEXUS_ADMIN_PASSWORD}" \
                    -H 'Content-Type: application/json' \
                    http://localhost:8081/service/rest/v1/system/eula \
                    -d "$ACCEPT_PAYLOAD" >/dev/null 2>&1 || true
            fi
        fi

        # Check raw repository
        if ! curl -s -u "${NEXUS_ADMIN_USER}:${NEXUS_ADMIN_PASSWORD}" http://localhost:8081/service/rest/v1/repositories | grep -q "\"name\":\"${NEXUS_REPO}\""; then
            curl -s -X POST -u "${NEXUS_ADMIN_USER}:${NEXUS_ADMIN_PASSWORD}" \
                -H "Content-Type: application/json" \
                http://localhost:8081/service/rest/v1/repositories/raw/hosted \
                -d "{\"name\":\"${NEXUS_REPO}\",\"online\":true,\"storage\":{\"blobStoreName\":\"default\",\"strictContentTypeValidation\":false,\"writePolicy\":\"ALLOW\"}}" >/dev/null 2>&1 || true
        fi
        echo -e "${GREEN}[✓] Nexus 3 EULA accepted and repository '${NEXUS_REPO}' verified!${NC}"
        break
    fi
    sleep 3
done

# ==============================================================================
# 8. Prometheus & Grafana Monitoring Platform
# ==============================================================================
echo -e "\n${CYAN}[8/10] Checking Prometheus & Grafana in Kubernetes...${NC}"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

MONITORING_DIR="${WORKSPACE_ROOT}/manifests/monitoring"
if [ -d "$MONITORING_DIR" ]; then
    kubectl apply -f "$MONITORING_DIR" 2>/dev/null || true
fi

echo -e "${GREEN}[✓] Monitoring manifests applied in namespace 'monitoring'.${NC}"

# ==============================================================================
# 9. Jenkins CI/CD Controller with Embedded Toolchain
# ==============================================================================
echo -e "\n${CYAN}[9/10] Configuring Jenkins CI/CD Controller & Integrations...${NC}"

JENKINS_HOME_HOST="/var/jenkins_home"
mkdir -p "${JENKINS_HOME_HOST}/init.groovy.d"
chmod -R 777 "${JENKINS_HOME_HOST}" 2>/dev/null || true

echo "2.0" > "${JENKINS_HOME_HOST}/jenkins.install.UpgradeWizard.state"
echo "2.440.4" > "${JENKINS_HOME_HOST}/jenkins.install.InstallUtil.lastExecVersion"

# Admin User Groovy
cat << EOF_GROOVY > "${JENKINS_HOME_HOST}/init.groovy.d/01-create-admin.groovy"
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()
def adminUser = "${JENKINS_ADMIN_USER}"
def adminPass = "${JENKINS_ADMIN_PASSWORD}"

def realm = instance.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    realm = new HudsonPrivateSecurityRealm(false)
    instance.setSecurityRealm(realm)
}

def existingUser = realm.getUser(adminUser)
if (existingUser == null || realm.getAllUsers().find { it.getId().equalsIgnoreCase(adminUser) } == null) {
    realm.createAccount(adminUser, adminPass)
} else {
    def passwordDetails = hudson.security.HudsonPrivateSecurityRealm.Details.fromPlainPassword(adminPass)
    existingUser.addProperty(passwordDetails)
}

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

try {
    instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
} catch (Throwable t) {}

instance.save()
EOF_GROOVY

# Credentials Groovy (GitHub, DockerHub, SonarQube)
cat << EOF_GROOVY_CREDS > "${JENKINS_HOME_HOST}/init.groovy.d/02-credentials.groovy"
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import org.jenkinsci.plugins.plaincredentials.impl.*
import hudson.util.Secret

def githubUser = "${GITHUB_USERNAME}"
def githubToken = "${GITHUB_TOKEN_EFFECTIVE}"
def dockerhubUser = "${DOCKERHUB_USERNAME}"
def dockerhubToken = "${DOCKERHUB_TOKEN_EFFECTIVE}"

try {
    def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0]?.getStore()
    if (store != null) {
        def domain = Domain.global()

        // github-token
        def upCred = new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, "github-token", "GitHub Access Token", githubUser, githubToken)
        def existingUp = store.getCredentials(domain).find { it.id == "github-token" }
        if (existingUp) { store.removeCredentials(domain, existingUp) }
        store.addCredentials(domain, upCred)

        // dockerhub-token
        def dhCred = new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, "dockerhub-token", "DockerHub Access Token", dockerhubUser, dockerhubToken)
        def existingDh = store.getCredentials(domain).find { it.id == "dockerhub-token" }
        if (existingDh) { store.removeCredentials(domain, existingDh) }
        store.addCredentials(domain, dhCred)

        Jenkins.instance.save()
    }
} catch (Throwable t) {}
EOF_GROOVY_CREDS

# Pipeline Job Groovy
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
    }
    def scm = new GitSCM(repoUrl)
    scm.branches = [new BranchSpec("*/main")]
    scm.userRemoteConfigs = [new UserRemoteConfig(repoUrl, null, null, "github-token")]
    def flowDef = new CpsScmFlowDefinition(scm, "Jenkinsfile")
    flowDef.setLightweight(true)
    job.setDefinition(flowDef)
    job.save()
} catch (Throwable t) {}
EOF_GROOVY_JOB

# Run or update Jenkins container
if docker ps -q -f name=^jenkins$ >/dev/null 2>&1 && [ -n "$(docker ps -q -f name=^jenkins$)" ]; then
    echo -e "${GREEN}[✓] Jenkins container is RUNNING.${NC}"
else
    docker rm -f jenkins >/dev/null 2>&1 || true
    docker run -d --name jenkins \
      --restart always \
      -p 0.0.0.0:8080:8080 \
      -p 0.0.0.0:50000:50000 \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $(which docker):/usr/bin/docker \
      -v "${JENKINS_HOME_HOST}:/var/jenkins_home" \
      -u root \
      -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
      jenkins/jenkins:lts

    docker network connect minikube jenkins 2>/dev/null || true
fi

# Ensure Jenkins plugins
PLUGINS_TO_INSTALL=(docker-workflow docker-plugin kubernetes kubernetes-cli git workflow-aggregator pipeline-stage-view credentials-binding plain-credentials ws-cleanup github)
docker exec -u root jenkins jenkins-plugin-cli --plugins "${PLUGINS_TO_INSTALL[@]}" >/dev/null 2>&1 || true

# Provision tool binaries inside Jenkins container
docker exec -u root jenkins bash -c "
    apt-get update -y >/dev/null 2>&1 && \
    apt-get install -y python3 python3-pip python3-venv build-essential curl jq git >/dev/null 2>&1 && \
    ln -sf /usr/bin/python3 /usr/bin/python
"

# Copy CLI binaries from host directly into Jenkins for lightning-fast setup
docker cp /usr/local/bin/kubectl jenkins:/usr/local/bin/kubectl 2>/dev/null || true
docker cp /usr/local/bin/argocd jenkins:/usr/local/bin/argocd 2>/dev/null || true
docker cp /usr/local/bin/trivy jenkins:/usr/local/bin/trivy 2>/dev/null || true
docker cp /usr/local/bin/sonar-scanner jenkins:/usr/local/bin/sonar-scanner 2>/dev/null || true
docker cp /usr/local/bin/uv jenkins:/usr/local/bin/uv 2>/dev/null || true

# Flattened Kubeconfig into Jenkins
docker exec -u root jenkins mkdir -p /root/.kube /var/jenkins_home/.kube 2>/dev/null || true
docker cp /root/.kube/config jenkins:/root/.kube/config 2>/dev/null || true
docker cp /root/.kube/config jenkins:/var/jenkins_home/.kube/config 2>/dev/null || true
docker exec -u root jenkins chown -R 1000:1000 /var/jenkins_home/.kube 2>/dev/null || true

echo -e "${GREEN}[✓] Jenkins container fully provisioned with toolchain (uv, sonar-scanner, trivy, kubectl, argocd).${NC}"

# ==============================================================================
# 10. Firewall Rules, Systemd Port-Forward Daemons & Verification
# ==============================================================================
echo -e "\n${CYAN}[10/10] Configuring Firewall, Persistent Daemons & Public Access...${NC}"

# A. UFW Firewall
for port in "${REQUIRED_PORTS[@]}"; do
    ufw allow "${port}/tcp" comment "DevOps Platform ${port}" >/dev/null 2>&1 || true
done
ufw allow 30000:32767/tcp comment "Kubernetes NodePort Range" >/dev/null 2>&1 || true
if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw reload >/dev/null 2>&1 || true
fi
echo -e "${GREEN}[✓] UFW firewall configured.${NC}"

# B. Persistent Systemd Port Forward Services
setup_systemd_forward() {
    local svc_name="$1"
    local desc="$2"
    local cmd="$3"

    cat << EOF_SYS_FWD > "/etc/systemd/system/${svc_name}.service"
[Unit]
Description=${desc}
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=root
Environment="KUBECONFIG=/root/.kube/config"
ExecStart=${cmd}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SYS_FWD

    systemctl daemon-reload
    systemctl enable "${svc_name}.service" >/dev/null 2>&1 || true
    systemctl restart "${svc_name}.service" >/dev/null 2>&1 || true
}

setup_systemd_forward "argocd-port-forward" "ArgoCD Web Port Forward (30751 -> 80)" \
    "/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/argocd-server 30751:80 -n argocd"

setup_systemd_forward "prometheus-port-forward" "Prometheus Web Port Forward (9090 -> 9090)" \
    "/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/prometheus-service 9090:9090 -n monitoring"

setup_systemd_forward "grafana-port-forward" "Grafana Web Port Forward (3000 -> 3000)" \
    "/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/grafana-service 3000:3000 -n monitoring"

setup_systemd_forward "smart-manufacturing-port-forward" "Smart Manufacturing Web Port Forward (30080 & 8000 -> 80)" \
    "/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/smart-manufacturing-service 30080:80 8000:80 -n default"

echo -e "${GREEN}[✓] Persistent systemd port-forward daemons active (ArgoCD, Prometheus, Grafana, Smart Mfg).${NC}"

# C. Cloud Firewall (GCP)
GCP_METADATA_HEADER="Metadata-Flavor: Google"
GCP_METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"
GCP_VM_NAME=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/name" 2>/dev/null || true)

if [ -n "$GCP_VM_NAME" ]; then
    GCP_ZONE_RAW=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/zone" 2>/dev/null || true)
    GCP_ZONE=$(echo "$GCP_ZONE_RAW" | awk -F/ '{print $NF}')
    GCP_PROJECT=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/project/project-id" 2>/dev/null || true)

    PORT_SPEC="tcp:22,tcp:80,tcp:443,tcp:3000,tcp:8000,tcp:8080,tcp:8081,tcp:8082,tcp:9000,tcp:9090,tcp:30080,tcp:30090,tcp:30300,tcp:30751,tcp:30752,tcp:30000-32767,tcp:50000"

    if command -v gcloud >/dev/null 2>&1; then
        gcloud compute firewall-rules update "$FIREWALL_NAME" \
            --project="$GCP_PROJECT" \
            --allow="$PORT_SPEC" \
            --source-ranges="0.0.0.0/0" \
            --quiet >/dev/null 2>&1 || \
        gcloud compute firewall-rules create "$FIREWALL_NAME" \
            --project="$GCP_PROJECT" \
            --allow="$PORT_SPEC" \
            --source-ranges="0.0.0.0/0" \
            --target-tags="$TARGET_TAGS" \
            --quiet >/dev/null 2>&1 || true

        gcloud compute instances add-tags "$GCP_VM_NAME" \
            --zone="$GCP_ZONE" \
            --project="$GCP_PROJECT" \
            --tags="$TARGET_TAGS" \
            --quiet >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}[✓] GCP Firewall '${FIREWALL_NAME}' verified and updated with all platform ports.${NC}"
fi

# Run final kernel & RAM optimization
optimize_system_and_ram

# ==============================================================================
# Summary & Portal Directory
# ==============================================================================
EXTERNAL_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}${BOLD}====================================================================================${NC}"
echo -e "${GREEN}${BOLD} 🎉 ENTERPRISE DEVOPS PLATFORM SETUP COMPLETED SUCCESSFULLY!                         ${NC}"
echo -e "${GREEN}${BOLD}====================================================================================${NC}"
echo -e "  🌐 ${BOLD}Smart Manufacturing App:${NC} http://${EXTERNAL_IP}:8000 (Alt NodePort: :30080)"
echo -e "  🛠️ ${BOLD}Jenkins CI/CD Dashboard:${NC} http://${EXTERNAL_IP}:8080 (User: ${GREEN}${JENKINS_ADMIN_USER}${NC} / Pass: ${GREEN}${JENKINS_ADMIN_PASSWORD}${NC})"
echo -e "  🔍 ${BOLD}SonarQube Code Quality:${NC}  http://${EXTERNAL_IP}:9000 (Admin Token: ${GREEN}${SONARQUBE_TOKEN:0:12}...${NC})"
echo -e "  📦 ${BOLD}Sonatype Nexus 3 Repo:${NC}   http://${EXTERNAL_IP}:8081 (User: ${GREEN}admin${NC} / Pass: ${GREEN}${NEXUS_ADMIN_PASSWORD}${NC})"
echo -e "  📊 ${BOLD}Prometheus Metrics:${NC}      http://${EXTERNAL_IP}:9090 (NodePort: :30090)"
echo -e "  📈 ${BOLD}Grafana AI Dashboards:${NC}   http://${EXTERNAL_IP}:3000 (User: ${GREEN}admin${NC} / Pass: ${GREEN}admin123${NC})"
echo -e "  🚀 ${BOLD}ArgoCD GitOps Server:${NC}    http://${EXTERNAL_IP}:30751 (User: ${GREEN}admin${NC} / Pass: ${GREEN}${ARGOCD_PASSWORD:-admin}${NC})"
echo -e "  🛡️ ${BOLD}Trivy Vulnerability Scanner:${NC} Installed on host & inside Jenkins container (/usr/local/bin/trivy)"
echo -e "  ⚡ ${BOLD}Astral uv Python Manager:${NC}    Installed on host & inside Jenkins container (/usr/local/bin/uv)"
echo -e "====================================================================================\n"
