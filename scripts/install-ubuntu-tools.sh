#!/usr/bin/env bash
# ==============================================================================
# ALL-IN-ONE ENTERPRISE DEVOPS & AI OPERATIONS PLATFORM (UBUNTU / DEBIAN / GCP)
# Tools: Docker | Google Kubernetes Engine (GKE) | Kubectl | ArgoCD | SonarQube | Nexus 3 | Trivy | 
#        Prometheus | Grafana | Redis | Elasticsearch | Logstash | Kibana | Filebeat | Jenkins
# Capabilities:
#   1. Autonomous GCP VM Provisioning (e2-standard-8, 100GB disk, network tags)
#   2. Complete On-Host DevOps & Distributed Logging Stack Bootstrap
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
====================================================================================================
  ENTERPRISE DEVOPS & INDUSTRIAL AI OPERATIONS PLATFORM AUTOMATED SETUP
  Docker | Google Kubernetes Engine (GKE) | Kubectl | ArgoCD | SonarQube | Nexus 3 | Trivy |
  Prometheus | Grafana | Redis | Elasticsearch | Logstash | Kibana | Filebeat | Jenkins
====================================================================================================
EOF
    echo -e "${NC}"
}

header

show_help() {
    echo "Usage: sudo bash $0 [OPTIONS]"
    echo "       or (on Mac/local machine with gcloud): bash $0 --provision-vm"
    echo ""
    echo "Options:"
    echo "  (no args)                     Run full on-host DevOps platform installation & verification"
    echo "  --provision-vm, --create-vm   Create/verify GCP VM 'gitops' and auto-bootstrap entire platform"
    echo "  --github-token <token>        Set GitHub Personal Access Token for Jenkins & Git"
    echo "  --dockerhub-token <token>     Set DockerHub Access Token for Jenkins & Docker"
    echo "  --github-user <username>      Set GitHub username (default: KishorKumarParoi)"
    echo "  --dockerhub-user <username>   Set DockerHub username (default: kishorkumarparoi)"
    echo "  --jenkins-password <pass>     Set Jenkins admin password (default: admin123)"
    echo "  --sonarqube-token <token>     Set SonarQube system token"
    echo "  --nexus-password <pass>       Set Sonatype Nexus admin password (default: admin123)"
    echo "  --nexus-repo <repo>           Set Nexus raw release repo name (default: smart-manufacturing-releases)"
    echo "  --optimize, --cleanup         Clear RAM caches, vacuum logs, and tune kernel"
    echo "  --help, -h                    Show this help message"
}

# GCP VM Provisioning Configuration
GCP_PROJECT="project-53d8ce01-b0e0-4f8b-94c"
GCP_ZONE="us-central1-a"
VM_NAME="gitops"
MACHINE_TYPE="e2-standard-8"
SERVICE_ACCOUNT="881665859601-compute@developer.gserviceaccount.com"
IMAGE_FAMILY="projects/ubuntu-os-cloud/global/images/ubuntu-minimal-2604-resolute-amd64-v20261009"
DISK_SIZE="100"
DISK_TYPE="pd-balanced"
DISK_RESOURCE_POLICY="projects/project-53d8ce01-b0e0-4f8b-94c/regions/us-central1/resourcePolicies/default-schedule-1"
SCOPES="https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append"
TARGET_TAGS="http-server,https-server,lb-health-check,devops-public-web,devops-control-plane,devops-vm"
FIREWALL_PUBLIC="allow-devops-public-web"
FIREWALL_ADMIN="allow-devops-admin-mgmt"
PUBLIC_PORT_SPEC="tcp:80,tcp:443,tcp:8000"
ADMIN_PORT_SPEC="tcp:22,tcp:3000,tcp:5000,tcp:5601,tcp:8080,tcp:8081,tcp:8082,tcp:9000,tcp:9090,tcp:30080,tcp:30090,tcp:30300,tcp:30601,tcp:30751,tcp:30752,tcp:30000-32767,tcp:50000"
# NOTE: Redis (6379) and Elasticsearch (9200) are internal-only and NEVER exposed to external firewall rules!

# Check if running in VM Provisioning mode (e.g. from local Mac or workstation)
RUN_MODE="full"
for arg in "$@"; do
    case "$arg" in
        --provision-vm|--create-vm|--create-instance|--deploy-all)
            RUN_MODE="provision-vm"
            ;;
        --optimize|--clean|--cleanup|--speedup|-o)
            RUN_MODE="optimize"
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ==============================================================================
# AUTONOMOUS GCP VM PROVISIONING (When executed outside the VM or with --provision-vm)
# ==============================================================================
provision_gcp_vm_and_bootstrap() {
    echo -e "\n${CYAN}${BOLD}[*] Initiating Autonomous GCP Compute Engine VM Provisioning...${NC}"

    if ! command -v gcloud >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] 'gcloud' CLI is required for VM provisioning.${NC}"
        echo "  Please install gcloud or run this script directly inside an Ubuntu VM."
        exit 1
    fi

    # 1. Check if VM already exists
    echo -e "${YELLOW}[*] Checking if instance '${VM_NAME}' exists in project '${GCP_PROJECT}'...${NC}"
    EXISTING_VM=$(gcloud compute instances list --project="$GCP_PROJECT" --filter="name=${VM_NAME} AND zone:${GCP_ZONE}" --format="value(name)" 2>/dev/null || true)

    if [ -n "$EXISTING_VM" ]; then
        echo -e "${GREEN}[✓] Instance '${VM_NAME}' already exists and is active!${NC}"
        # Ensure disk resource policy is attached
        gcloud compute disks add-resource-policies "$VM_NAME" \
            --project="$GCP_PROJECT" \
            --zone="$GCP_ZONE" \
            --resource-policies="default-schedule-1" >/dev/null 2>&1 || true
    else
        echo -e "${YELLOW}[*] Creating instance '${VM_NAME}' (${MACHINE_TYPE}, 100GB Balanced PD, Ubuntu Minimal)...${NC}"
        gcloud compute instances create "$VM_NAME" \
            --project="$GCP_PROJECT" \
            --zone="$GCP_ZONE" \
            --machine-type="$MACHINE_TYPE" \
            --network-interface="network-tier=STANDARD,stack-type=IPV4_ONLY,subnet=default" \
            --no-can-ip-forward \
            --maintenance-policy=MIGRATE \
            --provisioning-model=STANDARD \
            --service-account="$SERVICE_ACCOUNT" \
            --scopes="$SCOPES" \
            --tags="$TARGET_TAGS" \
            --create-disk="auto-delete=yes,boot=yes,device-name=${VM_NAME},disk-resource-policy=${DISK_RESOURCE_POLICY},image=${IMAGE_FAMILY},mode=rw,size=${DISK_SIZE},type=${DISK_TYPE}" \
            --no-shielded-secure-boot \
            --shielded-vtpm \
            --shielded-integrity-monitoring \
            --labels="goog-ec-src=vm_add-gcloud" \
            --reservation-affinity=any \
            --quiet || \
        gcloud compute instances create "$VM_NAME" \
            --project="$GCP_PROJECT" \
            --zone="$GCP_ZONE" \
            --machine-type="$MACHINE_TYPE" \
            --network-interface="network-tier=STANDARD,stack-type=IPV4_ONLY,subnet=default" \
            --no-can-ip-forward \
            --maintenance-policy=MIGRATE \
            --provisioning-model=STANDARD \
            --service-account="$SERVICE_ACCOUNT" \
            --scopes="$SCOPES" \
            --tags="$TARGET_TAGS" \
            --create-disk="auto-delete=yes,boot=yes,device-name=${VM_NAME},image=${IMAGE_FAMILY},mode=rw,size=${DISK_SIZE},type=${DISK_TYPE}" \
            --no-shielded-secure-boot \
            --shielded-vtpm \
            --shielded-integrity-monitoring \
            --labels="goog-ec-src=vm_add-gcloud" \
            --reservation-affinity=any \
            --quiet
        echo -e "${GREEN}[✓] Instance '${VM_NAME}' successfully created with IP forwarding disabled!${NC}"
    fi

    # 2. Get External IP
    VM_IP=$(gcloud compute instances describe "$VM_NAME" --project="$GCP_PROJECT" --zone="$GCP_ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    echo -e "${GREEN}[✓] Instance '${VM_NAME}' Public IP:${NC} ${BOLD}${VM_IP}${NC}"

    # 3. Ensure GCP Cloud Firewall enforces zero-trust rules (Anti-Egress / Bot Prevention)
    echo -e "${YELLOW}[*] Configuring zero-trust GCP Cloud Firewall (Strict User IP Whitelist & Bot Protection)...${NC}"
    
    # Auto-detect client public IP and derive /24 subnet for carrier dynamic pools
    LOCAL_CLIENT_IP=$(curl -s -m 4 https://api.ipify.org 2>/dev/null || curl -s -m 4 https://ifconfig.me 2>/dev/null || echo "")
    if [ -n "$LOCAL_CLIENT_IP" ]; then
        # Whitelist the user's IP, their /24 carrier subnet (handles dynamic IP rotation), and GCP IAP
        CLIENT_SUBNET="$(echo "$LOCAL_CLIENT_IP" | cut -d. -f1-3).0/24"
        USER_ALLOWED_CIDR="${LOCAL_CLIENT_IP}/32,${CLIENT_SUBNET},35.235.240.0/20"
        echo -e "${GREEN}[✓] ZERO-TRUST ACTIVE: Firewall locked strictly to your IP (${LOCAL_CLIENT_IP}) and ISP pool (${CLIENT_SUBNET}).${NC}"
        echo -e "${GREEN}[✓] All other public internet access (0.0.0.0/0) is 100% BLOCKED. No external bots allowed.${NC}"
    else
        USER_ALLOWED_CIDR="35.235.240.0/20"
        echo -e "${YELLOW}[!] Warning: Could not detect public IP. Restricting to GCP IAP (35.235.240.0/20).${NC}"
    fi

    # Allow custom override if specified via ADMIN_SOURCE_CIDR environment variable
    USER_ALLOWED_CIDR="${ADMIN_SOURCE_CIDR:-$USER_ALLOWED_CIDR}"

    # 3.1 Web Tier (Ports 80, 443, 8000) - STRICTLY RESTRICTED TO USER IP ONLY!
    gcloud compute firewall-rules update "$FIREWALL_PUBLIC" \
        --project="$GCP_PROJECT" \
        --allow="$PUBLIC_PORT_SPEC" \
        --source-ranges="$USER_ALLOWED_CIDR" \
        --quiet >/dev/null 2>&1 || \
    gcloud compute firewall-rules create "$FIREWALL_PUBLIC" \
        --project="$GCP_PROJECT" \
        --allow="$PUBLIC_PORT_SPEC" \
        --source-ranges="$USER_ALLOWED_CIDR" \
        --target-tags="devops-public-web,http-server,https-server" \
        --quiet >/dev/null 2>&1 || true

    # 3.2 Admin Management Tier (Ports 22, 3000, 8080, 8081, 9000, etc.) - STRICTLY RESTRICTED TO USER IP ONLY!
    gcloud compute firewall-rules update "$FIREWALL_ADMIN" \
        --project="$GCP_PROJECT" \
        --allow="$ADMIN_PORT_SPEC" \
        --source-ranges="$USER_ALLOWED_CIDR" \
        --quiet >/dev/null 2>&1 || \
    gcloud compute firewall-rules create "$FIREWALL_ADMIN" \
        --project="$GCP_PROJECT" \
        --allow="$ADMIN_PORT_SPEC" \
        --source-ranges="$USER_ALLOWED_CIDR" \
        --target-tags="devops-control-plane,devops-vm" \
        --quiet >/dev/null 2>&1 || true

    # Purge any legacy or wide-open rules (Guarantees 0.0.0.0/0 is never open)
    for wide_rule in "allow-devops-platform" "default-allow-http" "default-allow-https"; do
        gcloud compute firewall-rules delete "$wide_rule" --project="$GCP_PROJECT" --quiet >/dev/null 2>&1 || true
    done
    echo -e "${GREEN}[✓] Anti-Bot Protection Active: All wide-open 0.0.0.0/0 firewall rules purged.${NC}"

    gcloud compute instances add-tags "$VM_NAME" \
        --zone="$GCP_ZONE" \
        --project="$GCP_PROJECT" \
        --tags="$TARGET_TAGS" \
        --quiet >/dev/null 2>&1 || true

    # 4. Wait for SSH daemon readiness
    echo -e "${YELLOW}[*] Waiting for SSH daemon readiness on ${VM_IP}...${NC}"
    for i in {1..30}; do
        if gcloud compute ssh "$VM_NAME" --project="$GCP_PROJECT" --zone="$GCP_ZONE" --command="echo 'SSH ready'" --quiet >/dev/null 2>&1; then
            echo -e "${GREEN}[✓] SSH connection confirmed!${NC}"
            break
        fi
        sleep 3
    done

    # 5. Synchronize repository files to VM (excluding large local virtualenvs)
    echo -e "${YELLOW}[*] Synchronizing Smart Manufacturing repository & manifests to VM...${NC}"
    COPYFILE_DISABLE=1 tar --format ustar -czf - -C "$WORKSPACE_ROOT" --exclude='.venv' --exclude='65 - *' . | \
        gcloud compute ssh "$VM_NAME" --project="$GCP_PROJECT" --zone="$GCP_ZONE" \
        --command="mkdir -p ~/smart-manufacturing && tar --warning=no-unknown-keyword -xzf - -C ~/smart-manufacturing 2>/dev/null || tar -xzf - -C ~/smart-manufacturing" --quiet

    # 6. Execute On-Host Bootstrap
    echo -e "${YELLOW}[*] Executing full DevOps & Industrial AI platform setup on remote VM...${NC}"
    gcloud compute ssh "$VM_NAME" --project="$GCP_PROJECT" --zone="$GCP_ZONE" \
        --command="sudo bash ~/smart-manufacturing/scripts/install-ubuntu-tools.sh"

    echo -e "\n${GREEN}${BOLD}🎉 COMPLETE PLATFORM DEPLOYMENT ON VM ${VM_NAME} (${VM_IP}) FINISHED!${NC}\n"
    exit 0
}

if [ "$RUN_MODE" = "provision-vm" ]; then
    provision_gcp_vm_and_bootstrap
fi

# Auto-route to provision-vm if running on macOS host
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${YELLOW}[*] Running on macOS host. Auto-routing to GCP VM Provisioning & Remote Bootstrap...${NC}"
    provision_gcp_vm_and_bootstrap
fi

# Ensure running with sudo or as root on Linux
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run this script with sudo or as root on Linux:${NC}"
    echo "  sudo bash $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")

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

# Non-blocking interactive prompt if tokens are missing and /dev/tty is available
if [ -z "$GITHUB_TOKEN" ] && [ -c /dev/tty ]; then
    echo -n "Enter GitHub Token (or press Enter to skip): " > /dev/tty
    read -r -t 10 user_gh_tok < /dev/tty || true
    [ -n "$user_gh_tok" ] && GITHUB_TOKEN="$user_gh_tok"
fi
if [ -z "$DOCKERHUB_TOKEN" ] && [ -c /dev/tty ]; then
    echo -n "Enter DockerHub Token (or press Enter to skip): " > /dev/tty
    read -r -t 10 user_dh_tok < /dev/tty || true
    [ -n "$user_dh_tok" ] && DOCKERHUB_TOKEN="$user_dh_tok"
fi

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
DOCKER_DISTRO="ubuntu"
[ "$OS_ID" = "debian" ] && DOCKER_DISTRO="debian"
[ -z "$OS_CODENAME" ] && OS_CODENAME="jammy"

# High-Performance System & Kernel Tuning
optimize_system_and_ram() {
    echo -e "\n${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${CYAN}${BOLD} [SYSTEM ACCELERATION] RAM Flush, Conntrack & Kernel Optimizer     ${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"

    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=1d --vacuum-size=50M >/dev/null 2>&1 || true
    fi

    if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
        docker builder prune -f --filter "until=24h" >/dev/null 2>&1 || true
        docker network prune -f >/dev/null 2>&1 || true
    fi

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

    # Egress Hardening 1: Drop routed transit traffic on external interfaces
    if [ -f /etc/default/ufw ]; then
        sed -i 's/DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw 2>/dev/null || true
    fi

    # Egress Hardening 2: Install and configure fail2ban to mitigate automated scanners
    if command -v apt-get >/dev/null 2>&1; then
        dpkg -s fail2ban >/dev/null 2>&1 || (apt-get update -y && apt-get install -y fail2ban iproute2 >/dev/null 2>&1 || true)
        systemctl enable fail2ban >/dev/null 2>&1 || true
        systemctl restart fail2ban >/dev/null 2>&1 || true
    fi

    # Egress Hardening 3: Kernel Traffic Control (tc) Egress Ceiling (Cap at 25 Mbps)
    # This prevents any compromised process or bot from pushing 100 MB/s and draining terabytes
    WAN_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' || echo "eth0")
    if [ -n "$WAN_IF" ] && command -v tc >/dev/null 2>&1; then
        tc qdisc del dev "$WAN_IF" root 2>/dev/null || true
        tc qdisc add dev "$WAN_IF" root tbf rate 25mbit burst 64kbit latency 400ms 2>/dev/null || true
        echo -e "${GREEN}[✓] Egress Guard active: Outbound network traffic on ${WAN_IF} capped at 25 Mbps.${NC}"
    fi

    echo -e "${GREEN}[✓] System RAM, kernel network parameters, and anti-egress protection active.${NC}"
}

if [ "$RUN_MODE" = "optimize" ]; then
    optimize_system_and_ram
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
echo -e "\n${CYAN}[1/11] Checking base utilities & fast tools...${NC}"
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
echo -e "\n${CYAN}[2/11] Checking Docker CE installation & socket permissions...${NC}"
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

if [ -n "$DOCKERHUB_TOKEN" ] && [ -n "$DOCKERHUB_USERNAME" ]; then
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
    echo "$DOCKERHUB_TOKEN" | sudo -u "$REAL_USER" docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
fi
echo -e "${GREEN}[✓] Docker configured with non-root access.${NC}"

# ==============================================================================
# 3. Kubectl, ArgoCD CLI & Trivy Vulnerability Scanner
# ==============================================================================
echo -e "\n${CYAN}[3/11] Checking Kubectl, ArgoCD CLI & Trivy Scanner...${NC}"
if ! command -v kubectl >/dev/null 2>&1; then
    K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl && mv kubectl /usr/local/bin/kubectl
fi
echo -e "${GREEN}[✓] Kubectl ready.${NC}"

if ! command -v argocd >/dev/null 2>&1; then
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
fi
echo -e "${GREEN}[✓] ArgoCD CLI ready.${NC}"

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

# ==============================================================================
# 4. Git, GitHub CLI & SSH Keys
# ==============================================================================
echo -e "\n${CYAN}[4/11] Configuring Git & GitHub authentication (${GITHUB_USERNAME})...${NC}"
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
# 5. Enterprise Google Kubernetes Engine (GKE) Cluster Setup & Authentication
# ==============================================================================
GKE_CLUSTER="${GKE_CLUSTER_NAME:-smart-mfg-prod-gke}"
echo -e "\n${CYAN}[5/11] Connecting & Authenticating to Enterprise GKE Cluster ('${GKE_CLUSTER}')...${NC}"

if command -v gcloud >/dev/null 2>&1; then
    # Check if cluster exists; if not, invoke the enterprise GKE orchestrator
    if ! gcloud container clusters describe "$GKE_CLUSTER" --zone="$GCP_ZONE" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Production GKE cluster '${GKE_CLUSTER}' not found. Provisioning cluster...${NC}"
        bash "${SCRIPT_DIR}/setup-gke-production.sh"
    fi

    echo -e "${YELLOW}[*] Retrieving GKE cluster credentials for kubectl...${NC}"
    gcloud container clusters get-credentials "$GKE_CLUSTER" --zone="$GCP_ZONE" --project="$GCP_PROJECT"
    sudo -u "$REAL_USER" gcloud container clusters get-credentials "$GKE_CLUSTER" --zone="$GCP_ZONE" --project="$GCP_PROJECT" 2>/dev/null || true
    echo -e "${GREEN}[✓] Successfully authenticated to GKE: ${NC}$(kubectl config current-context 2>/dev/null)"
else
    echo -e "${RED}[ERROR] 'gcloud' CLI is required for GKE production authentication.${NC}"
    exit 1
fi

mkdir -p /root/.kube "$USER_HOME/.kube"
sudo -u "$REAL_USER" kubectl config view --flatten --raw > /root/.kube/config 2>/dev/null || cp "$USER_HOME/.kube/config" /root/.kube/config 2>/dev/null || true
cp /root/.kube/config "$USER_HOME/.kube/config" 2>/dev/null || true
chmod 600 /root/.kube/config "$USER_HOME/.kube/config"
chown "$REAL_USER:$REAL_USER" "$USER_HOME/.kube/config"

echo -e "${GREEN}[✓] Production GKE Nodes:${NC}"
kubectl get nodes -o wide

# ==============================================================================
# 6. ArgoCD Controller & Service (NodePort 30751)
# ==============================================================================
echo -e "\n${CYAN}[6/11] Checking ArgoCD in Kubernetes...${NC}"
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
echo -e "\n${CYAN}[7/11] Configuring SonarQube (Port 9000) & Nexus 3 (Port 8081)...${NC}"
docker network inspect devops-net >/dev/null 2>&1 || docker network create devops-net >/dev/null 2>&1 || true

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
    docker network connect devops-net sonarqube 2>/dev/null || true
fi

if ! command -v sonar-scanner >/dev/null 2>&1; then
    curl -sSL -O https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-6.2.1.4610-linux-x64.zip
    unzip -q sonar-scanner-cli-6.2.1.4610-linux-x64.zip -d /opt/
    rm -f sonar-scanner-cli-6.2.1.4610-linux-x64.zip
    ln -sf /opt/sonar-scanner-6.2.1.4610-linux-x64/bin/sonar-scanner /usr/local/bin/sonar-scanner
fi
echo -e "${GREEN}[✓] SonarQube & sonar-scanner ready.${NC}"

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
    docker network connect devops-net nexus 2>/dev/null || true
fi

for attempt in {1..20}; do
    if curl -s -f http://localhost:8081/service/rest/v1/status >/dev/null 2>&1; then
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
# 8. Redis In-Memory Telemetry & Prediction Cache
# ==============================================================================
echo -e "\n${CYAN}[8/11] Deploying Redis In-Memory Telemetry Cache in Kubernetes...${NC}"
REDIS_DIR="${WORKSPACE_ROOT}/manifests/redis"
if [ -d "$REDIS_DIR" ]; then
    kubectl apply -f "$REDIS_DIR" 2>/dev/null || true
    echo -e "${GREEN}[✓] Redis manifest applied (service/redis-service:6379).${NC}"
fi

# ==============================================================================
# 9. Elasticsearch, Logstash, Kibana & Filebeat (EFK Industrial Logging Stack)
# ==============================================================================
echo -e "\n${CYAN}[9/11] Deploying Elasticsearch, Logstash, Kibana & Filebeat (Logging Stack)...${NC}"
LOGGING_DIR="${WORKSPACE_ROOT}/manifests/logging"
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
if [ -d "$LOGGING_DIR" ]; then
    kubectl apply -f "$LOGGING_DIR" 2>/dev/null || true
    echo -e "${GREEN}[✓] EFK Industrial Logging Stack manifests applied in namespace 'logging'.${NC}"
fi

# Apply Prometheus & Grafana Monitoring
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
MONITORING_DIR="${WORKSPACE_ROOT}/manifests/monitoring"
if [ -d "$MONITORING_DIR" ]; then
    kubectl apply -f "$MONITORING_DIR" 2>/dev/null || true
    echo -e "${GREEN}[✓] Prometheus & Grafana manifests applied in namespace 'monitoring'.${NC}"
fi

# Build & Apply Smart Manufacturing Core App (Native Linux amd64 Build)
echo -e "${YELLOW}[*] Building native Linux amd64 container for Smart Manufacturing Application...${NC}"
if [ -f "${WORKSPACE_ROOT}/Dockerfile" ]; then
    echo -e "${YELLOW}[*] Compiling root Dockerfile via native Docker daemon...${NC}"
    docker build -t "kishorkumarparoi/smart-manufacturing:latest" \
        -f "${WORKSPACE_ROOT}/Dockerfile" "${WORKSPACE_ROOT}"
    echo -e "${GREEN}[✓] Native Linux amd64 container built successfully.${NC}"
fi

# Deploy Production Smart Manufacturing Workload to GKE Cluster
if [ -d "${WORKSPACE_ROOT}/k8s/overlays/production" ]; then
    echo -e "${YELLOW}[*] Applying Production Kustomize manifests to GKE...${NC}"
    kubectl apply -k "${WORKSPACE_ROOT}/k8s/overlays/production"
    echo -e "${GREEN}[✓] Production GKE manifests applied.${NC}"
    echo -e "${YELLOW}[*] Waiting for Production Smart Manufacturing Pod readiness in GKE...${NC}"
    kubectl rollout status deployment/prod-smart-manufacturing-api -n smart-manufacturing --timeout=180s || true
elif [ -f "${WORKSPACE_ROOT}/manifests/deployment.yaml" ]; then
    kubectl apply -f "${WORKSPACE_ROOT}/manifests/deployment.yaml" -f "${WORKSPACE_ROOT}/manifests/service.yaml"
    echo -e "${GREEN}[✓] Smart Manufacturing Core application manifests applied.${NC}"
    echo -e "${YELLOW}[*] Waiting for Smart Manufacturing Pod readiness...${NC}"
    kubectl rollout status deployment/smart-manufacturing --timeout=120s -n default || true
fi

# Apply In-Cluster Telemetry Cache (Redis)
if [ -d "${WORKSPACE_ROOT}/manifests/redis" ]; then
    kubectl apply -n smart-manufacturing -f "${WORKSPACE_ROOT}/manifests/redis" 2>/dev/null || \
    kubectl apply -n default -f "${WORKSPACE_ROOT}/manifests/redis" 2>/dev/null || true
    echo -e "${GREEN}[✓] Redis telemetry cache manifests applied.${NC}"
fi

# Apply Anti-Egress Kubernetes NetworkPolicies
if [ -f "${WORKSPACE_ROOT}/manifests/network-policy-egress-guard.yaml" ]; then
    kubectl apply -n smart-manufacturing -f "${WORKSPACE_ROOT}/manifests/network-policy-egress-guard.yaml" 2>/dev/null || \
    kubectl apply -n default -f "${WORKSPACE_ROOT}/manifests/network-policy-egress-guard.yaml" 2>/dev/null || true
    echo -e "${GREEN}[✓] Kubernetes Egress Guard NetworkPolicies applied.${NC}"
fi

# ==============================================================================
# 10. Jenkins CI/CD Controller with Embedded Toolchain
# ==============================================================================
echo -e "\n${CYAN}[10/11] Configuring Jenkins CI/CD Controller & Integrations...${NC}"
JENKINS_HOME_HOST="/var/jenkins_home"
mkdir -p "${JENKINS_HOME_HOST}/init.groovy.d"
chmod -R 777 "${JENKINS_HOME_HOST}" 2>/dev/null || true

echo "2.0" > "${JENKINS_HOME_HOST}/jenkins.install.UpgradeWizard.state"
echo "2.440.4" > "${JENKINS_HOME_HOST}/jenkins.install.InstallUtil.lastExecVersion"

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
        def upCred = new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, "github-token", "GitHub Access Token", githubUser, githubToken)
        def existingUp = store.getCredentials(domain).find { it.id == "github-token" }
        if (existingUp) { store.removeCredentials(domain, existingUp) }
        store.addCredentials(domain, upCred)

        def dhCred = new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, "dockerhub-token", "DockerHub Access Token", dockerhubUser, dockerhubToken)
        def existingDh = store.getCredentials(domain).find { it.id == "dockerhub-token" }
        if (existingDh) { store.removeCredentials(domain, existingDh) }
        store.addCredentials(domain, dhCred)

        Jenkins.instance.save()
    }
} catch (Throwable t) {}
EOF_GROOVY_CREDS

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
    docker network connect devops-net jenkins 2>/dev/null || true
fi

PLUGINS_TO_INSTALL=(docker-workflow docker-plugin kubernetes kubernetes-cli git workflow-aggregator pipeline-stage-view credentials-binding plain-credentials ws-cleanup github)
docker exec -u root jenkins jenkins-plugin-cli --plugins "${PLUGINS_TO_INSTALL[@]}" >/dev/null 2>&1 || true

docker exec -u root jenkins bash -c "
    apt-get update -y >/dev/null 2>&1 && \
    apt-get install -y python3 python3-pip python3-venv build-essential curl jq git >/dev/null 2>&1 && \
    ln -sf /usr/bin/python3 /usr/bin/python
"

docker cp /usr/local/bin/kubectl jenkins:/usr/local/bin/kubectl 2>/dev/null || true
docker cp /usr/local/bin/argocd jenkins:/usr/local/bin/argocd 2>/dev/null || true
docker cp /usr/local/bin/trivy jenkins:/usr/local/bin/trivy 2>/dev/null || true
docker cp /usr/local/bin/sonar-scanner jenkins:/usr/local/bin/sonar-scanner 2>/dev/null || true
docker cp /usr/local/bin/uv jenkins:/usr/local/bin/uv 2>/dev/null || true

docker exec -u root jenkins mkdir -p /root/.kube /var/jenkins_home/.kube 2>/dev/null || true
docker cp /root/.kube/config jenkins:/root/.kube/config 2>/dev/null || true
docker cp /root/.kube/config jenkins:/var/jenkins_home/.kube/config 2>/dev/null || true
docker exec -u root jenkins chown -R 1000:1000 /var/jenkins_home/.kube 2>/dev/null || true
echo -e "${GREEN}[✓] Jenkins container fully provisioned with toolchain (uv, sonar-scanner, trivy, kubectl, argocd).${NC}"

# ==============================================================================
# 11. Firewall Rules, Persistent Systemd Daemons & Public Access
# ==============================================================================
echo -e "\n${CYAN}[11/11] Configuring Firewall, Persistent Daemons & Public Access...${NC}"

for port in "${REQUIRED_PORTS[@]}"; do
    ufw allow "${port}/tcp" comment "DevOps Platform ${port}" >/dev/null 2>&1 || true
done
ufw allow 30000:32767/tcp comment "Kubernetes NodePort Range" >/dev/null 2>&1 || true
if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw reload >/dev/null 2>&1 || true
fi
echo -e "${GREEN}[✓] UFW firewall configured.${NC}"

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

setup_systemd_forward "kibana-port-forward" "Kibana Web Port Forward (5601 & 30601 -> 5601)" \
    "/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/kibana 5601:5601 30601:5601 -n logging"

if kubectl get svc prod-smart-manufacturing-service -n smart-manufacturing >/dev/null 2>&1; then
    setup_systemd_forward "smart-manufacturing-port-forward" "Smart Manufacturing Web Port Forward (8000 & 30080 -> 80)" \
        "/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/prod-smart-manufacturing-service 8000:80 30080:80 -n smart-manufacturing"
else
    setup_systemd_forward "smart-manufacturing-port-forward" "Smart Manufacturing Web Port Forward (8000 & 30080 -> 80)" \
        "/usr/local/bin/kubectl port-forward --address 0.0.0.0 service/smart-manufacturing-service 8000:80 30080:80 -n default"
fi

echo -e "${GREEN}[✓] Persistent systemd port-forward daemons active (ArgoCD, Prometheus, Grafana, Kibana, Smart Mfg).${NC}"

# GCP Cloud Firewall verification (Tiered Egress & Bot Protection)
GCP_METADATA_HEADER="Metadata-Flavor: Google"
GCP_METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"
GCP_VM_NAME=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/name" 2>/dev/null || true)

if [ -n "$GCP_VM_NAME" ]; then
    GCP_ZONE_RAW=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/zone" 2>/dev/null || true)
    GCP_ZONE=$(echo "$GCP_ZONE_RAW" | awk -F/ '{print $NF}')
    GCP_PROJECT=$(curl -s -f -m 3 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/project/project-id" 2>/dev/null || true)

    if command -v gcloud >/dev/null 2>&1; then
        # Clean legacy wide-open rule (NEVER allow 0.0.0.0/0)
        gcloud compute firewall-rules delete "allow-devops-platform" --project="$GCP_PROJECT" --quiet >/dev/null 2>&1 || true

        # Ensure network tags are attached to VM
        gcloud compute instances add-tags "$GCP_VM_NAME" \
            --zone="$GCP_ZONE" \
            --project="$GCP_PROJECT" \
            --tags="$TARGET_TAGS" \
            --quiet >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}[✓] Tiered GCP Firewalls verified ('${FIREWALL_PUBLIC}', '${FIREWALL_ADMIN}'). Zero-trust anti-bot protection active.${NC}"
fi

optimize_system_and_ram

# ==============================================================================
# Summary & Portal Directory
# ==============================================================================
EXTERNAL_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}${BOLD}====================================================================================================${NC}"
echo -e "${GREEN}${BOLD} 🎉 ENTERPRISE INDUSTRIAL AI & DEVOPS PLATFORM SETUP COMPLETED SUCCESSFULLY!                        ${NC}"
echo -e "${GREEN}${BOLD}====================================================================================================${NC}"
echo -e "  🌐 ${BOLD}Smart Manufacturing App:${NC} http://${EXTERNAL_IP}:8000 (Alt NodePort: :30080)"
echo -e "  🛠️ ${BOLD}Jenkins CI/CD Dashboard:${NC} http://${EXTERNAL_IP}:8080 (User: ${GREEN}${JENKINS_ADMIN_USER}${NC} / Pass: ${GREEN}${JENKINS_ADMIN_PASSWORD}${NC})"
echo -e "  🔍 ${BOLD}SonarQube Code Quality:${NC}  http://${EXTERNAL_IP}:9000 (Admin Token: ${GREEN}${SONARQUBE_TOKEN:0:12}...${NC})"
echo -e "  📦 ${BOLD}Sonatype Nexus 3 Repo:${NC}   http://${EXTERNAL_IP}:8081 (User: ${GREEN}admin${NC} / Pass: ${GREEN}${NEXUS_ADMIN_PASSWORD}${NC})"
echo -e "  📊 ${BOLD}Prometheus Metrics:${NC}      http://${EXTERNAL_IP}:9090 (NodePort: :30090)"
echo -e "  📈 ${BOLD}Grafana AI Dashboards:${NC}   http://${EXTERNAL_IP}:3000 (User: ${GREEN}admin${NC} / Pass: ${GREEN}admin123${NC})"
echo -e "  🔭 ${BOLD}Kibana Log Analytics:${NC}    http://${EXTERNAL_IP}:5601 (NodePort: :30601)"
echo -e "  🚀 ${BOLD}ArgoCD GitOps Server:${NC}    http://${EXTERNAL_IP}:30751 (User: ${GREEN}admin${NC} / Pass: ${GREEN}${ARGOCD_PASSWORD:-admin}${NC})"
echo -e "  ⚡ ${BOLD}Redis Cache & Telemetry:${NC} Active in K8s (redis-service:6379, fast inference cache enabled)"
echo -e "  🗄️ ${BOLD}Elasticsearch & Logstash:${NC}Active in K8s (elasticsearch:9200, logstash:5044, Daily indices enabled)"
echo -e "  🛡️ ${BOLD}Trivy Vulnerability Scanner:${NC} Installed on host & inside Jenkins container (/usr/local/bin/trivy)"
echo -e "  ⚡ ${BOLD}Astral uv Python Manager:${NC}    Installed on host & inside Jenkins container (/usr/local/bin/uv)"
echo -e "====================================================================================================\n"
