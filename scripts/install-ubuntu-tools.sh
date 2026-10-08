#!/usr/bin/env bash
# ==============================================================================
# ALL-IN-ONE UBUNTU DEVOPS SETUP SCRIPT
# Docker | Minikube | Kubectl | ArgoCD CLI & Server | Jenkins | Firewall Rules
# Target OS: Ubuntu 20.04 / 22.04 / 24.04 LTS (x86_64)
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
  DEVOPS PLATFORM AUTOMATED SETUP FOR UBUNTU
  Docker | Minikube | Kubectl | ArgoCD | Jenkins | Firewall Rules
==================================================================
EOF
    echo -e "${NC}"
}

header

# Ensure running with sudo or as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run this script with sudo or as root:${NC}"
    echo "  sudo bash $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo -e "${YELLOW}[*] Installing DevOps toolchain for user:${NC} ${BOLD}${REAL_USER}${NC}"

# ==============================================================================
# 1. Update Apt & Install Base Dependencies
# ==============================================================================
echo -e "\n${CYAN}[1/6] Updating packages and installing baseline utilities...${NC}"
apt-get update -y
apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    conntrack \
    git \
    jq

# ==============================================================================
# 2. Install Docker CE & Configure Permissions
# ==============================================================================
echo -e "\n${CYAN}[2/6] Installing Docker CE and Docker Compose Plugin...${NC}"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# Add user to docker group
usermod -aG docker "$REAL_USER"
chmod 666 /var/run/docker.sock || true
echo -e "${GREEN}[✓] Docker installed successfully! (${NC}$(docker --version)${GREEN})${NC}"

# ==============================================================================
# 3. Install Kubectl & ArgoCD CLI on Host
# ==============================================================================
echo -e "\n${CYAN}[3/6] Installing Kubectl and ArgoCD CLI on host...${NC}"

# Kubectl
K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl

# ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Configure aliases & autocompletion
if ! grep -q "alias k=kubectl" "$USER_HOME/.bashrc" 2>/dev/null; then
    echo "alias k=kubectl" >> "$USER_HOME/.bashrc"
    echo "complete -o default -F __start_kubectl k" >> "$USER_HOME/.bashrc"
    echo "source <(kubectl completion bash)" >> "$USER_HOME/.bashrc"
fi
echo -e "${GREEN}[✓] Kubectl installed: ${NC}$(kubectl version --client --output=yaml | grep gitVersion | head -n 1)"
echo -e "${GREEN}[✓] ArgoCD CLI installed: ${NC}$(argocd version --client --short 2>/dev/null || echo 'installed')"

# ==============================================================================
# 4. Install & Start Minikube (Docker Driver)
# ==============================================================================
echo -e "\n${CYAN}[4/6] Installing Minikube & Bootstrapping Cluster...${NC}"
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
rm -f minikube-linux-amd64

echo -e "${YELLOW}[*] Starting Minikube cluster using Docker driver (creates 'minikube' network)...${NC}"
sudo -u "$REAL_USER" minikube config set driver docker
sudo -u "$REAL_USER" minikube start --driver=docker

# Configure kubeconfig for root as well
mkdir -p /root/.kube
cp "$USER_HOME/.kube/config" /root/.kube/config
chown -R root:root /root/.kube

echo -e "${GREEN}[✓] Minikube cluster is UP! Nodes:${NC}"
kubectl get nodes

# ==============================================================================
# 5. Deploy & Configure ArgoCD on Minikube
# ==============================================================================
echo -e "\n${CYAN}[5/6] Deploying ArgoCD on Kubernetes (Minikube)...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo -e "${YELLOW}[*] Waiting for ArgoCD server deployment to be ready...${NC}"
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s || true

# Patch ArgoCD Server service to NodePort 30751 for external browser access
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 8080, "nodePort": 30751}, {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30752}]}}'

# Extract initial admin password
echo -e "${YELLOW}[*] Retrieving ArgoCD initial admin password...${NC}"
ARGOCD_PASSWORD=""
for i in {1..12}; do
    ARGOCD_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)
    if [ -n "$ARGOCD_PASSWORD" ]; then
        break
    fi
    sleep 5
done

# ==============================================================================
# 6. Deploy Jenkins Container (Root, Docker-in-Docker, Minikube Network)
# ==============================================================================
echo -e "\n${CYAN}[6/6] Deploying Jenkins Container connected to Minikube Network...${NC}"

# Stop existing container if present
docker rm -f jenkins 2>/dev/null || true

DOCKER_GID=$(getent group docker | cut -d: -f3)

docker run -d --name jenkins \
  --restart always \
  -p 8080:8080 \
  -p 50000:50000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(which docker):/usr/bin/docker \
  -u root \
  -e DOCKER_GID="${DOCKER_GID}" \
  --network minikube \
  jenkins/jenkins:lts

echo -e "${YELLOW}[*] Waiting for Jenkins container to initialize...${NC}"
sleep 15

echo -e "${YELLOW}[*] Installing Python 3, pip, venv, Kubectl & ArgoCD CLI inside Jenkins container...${NC}"
docker exec -u root jenkins bash -c "
  apt update -y && \
  apt install -y python3 python3-pip python3-venv curl jq && \
  ln -sf /usr/bin/python3 /usr/bin/python && \
  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && \
  chmod +x kubectl && mv kubectl /usr/local/bin/kubectl && \
  curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && \
  chmod +x /usr/local/bin/argocd
"

# Copy Kubeconfig into Jenkins container so pipelines can interact with Minikube
echo -e "${YELLOW}[*] Configuring Kubeconfig inside Jenkins container...${NC}"
docker exec -u root jenkins mkdir -p /root/.kube /var/jenkins_home/.kube
docker cp /root/.kube/config jenkins:/root/.kube/config
docker cp /root/.kube/config jenkins:/var/jenkins_home/.kube/config
docker exec -u root jenkins chown -R 1000:1000 /var/jenkins_home/.kube

# Retrieve Jenkins Initial Admin Password
JENKINS_PASSWORD=""
for i in {1..12}; do
    JENKINS_PASSWORD=$(docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true)
    if [ -n "$JENKINS_PASSWORD" ]; then
        break
    fi
    sleep 5
done

# ==============================================================================
# 7. Automatic Firewall Configuration (GCP "allow-devops-platform" & UFW)
# ==============================================================================
echo -e "\n${CYAN}[7/7] Configuring automatic firewall rules ('allow-devops-platform') & persistent exposure...${NC}"

FIREWALL_NAME="${FIREWALL_NAME:-allow-devops-platform}"
TARGET_TAGS="allow-devops-platform,devops-control-plane,devops-vm"
REQUIRED_PORTS=(22 80 443 8000 8080 8081 9000 30080 30751 30752 50000)

# A. Configure Local OS Firewall (UFW)
echo -e "${YELLOW}[*] Configuring Ubuntu UFW local firewall for DevOps ports...${NC}"
command -v ufw >/dev/null 2>&1 || apt-get install -y --no-install-recommends ufw
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
echo -e "${YELLOW}[*] Setting up persistent background port-forwarding for ArgoCD (Port 30751)...${NC}"
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
echo -e "${GREEN}[✓] ArgoCD background port-forward service active on 0.0.0.0:30751!${NC}"

# C. Automatic Cloud Firewall (GCP)
GCP_METADATA_HEADER="Metadata-Flavor: Google"
GCP_METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"
GCP_VM_NAME=$(curl -s -f -m 2 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/name" 2>/dev/null || true)

if [ -n "$GCP_VM_NAME" ]; then
    GCP_ZONE_RAW=$(curl -s -f -m 2 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/zone" 2>/dev/null || true)
    GCP_ZONE=$(echo "$GCP_ZONE_RAW" | awk -F/ '{print $NF}')
    GCP_PROJECT=$(curl -s -f -m 2 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/project/project-id" 2>/dev/null || true)
    
    echo -e "${GREEN}[✓] Google Cloud VM detected:${NC} ${BOLD}${GCP_VM_NAME}${NC} (Zone: ${GCP_ZONE}, Project: ${GCP_PROJECT})"

    # Ensure gcloud CLI is available
    if ! command -v gcloud >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Installing Google Cloud SDK CLI...${NC}"
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null 2>&1 || true
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg --yes >/dev/null 2>&1 || true
        apt-get update -y >/dev/null 2>&1 && apt-get install -y google-cloud-sdk >/dev/null 2>&1 || true
    fi

    # Attach firewall target tags to this instance
    if command -v gcloud >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Attaching network tags '${TARGET_TAGS}' to GCP instance '${GCP_VM_NAME}'...${NC}"
        gcloud compute instances add-tags "$GCP_VM_NAME" \
            --zone="$GCP_ZONE" \
            --tags="$TARGET_TAGS" \
            --quiet >/dev/null 2>&1 || true

        echo -e "${YELLOW}[*] Synchronizing GCP firewall rule '${FIREWALL_NAME}'...${NC}"
        PORT_SPEC="tcp:22,tcp:80,tcp:443,tcp:8000,tcp:8080,tcp:8081,tcp:9000,tcp:30080,tcp:30751,tcp:30752,tcp:30000-32767,tcp:50000"
        
        if gcloud compute firewall-rules describe "$FIREWALL_NAME" ${GCP_PROJECT:+--project="$GCP_PROJECT"} >/dev/null 2>&1; then
            gcloud compute firewall-rules update "$FIREWALL_NAME" \
                ${GCP_PROJECT:+--project="$GCP_PROJECT"} \
                --allow="$PORT_SPEC" \
                --target-tags="$TARGET_TAGS" \
                --quiet >/dev/null 2>&1 || true
            echo -e "${GREEN}[✓] GCP Firewall rule '${FIREWALL_NAME}' verified & updated with all DevOps ports!${NC}"
        else
            gcloud compute firewall-rules create "$FIREWALL_NAME" \
                ${GCP_PROJECT:+--project="$GCP_PROJECT"} \
                --direction=INGRESS \
                --priority=1000 \
                --network=default \
                --action=ALLOW \
                --rules="$PORT_SPEC" \
                --source-ranges=0.0.0.0/0 \
                --target-tags="$TARGET_TAGS" \
                --description="Automated DevOps Platform Firewall Rules" \
                --quiet >/dev/null 2>&1 || true
            echo -e "${GREEN}[✓] GCP Firewall rule '${FIREWALL_NAME}' created and applied to this VM!${NC}"
        fi
    else
        echo -e "${YELLOW}[!] gcloud CLI is not installed or lacks credentials on this VM.${NC}"
    fi
else
    echo -e "${YELLOW}[*] Standalone Ubuntu environment (non-GCP). Local UFW firewall rules are active.${NC}"
fi

# ==============================================================================
# Summary & Next Steps
# ==============================================================================
EXTERNAL_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD} ✓ SETUP COMPLETED SUCCESSFULLY!                                  ${NC}"
echo -e "${GREEN}${BOLD}==================================================================${NC}"
echo -e "  • ${BOLD}Docker:${NC}        $(docker --version)"
echo -e "  • ${BOLD}Minikube:${NC}      $(minikube version --short)"
echo -e "  • ${BOLD}Kubectl:${NC}       $(kubectl version --client --output=yaml | grep gitVersion | head -n 1 | awk '{print $2}')"
echo -e "  • ${BOLD}Jenkins:${NC}       http://${EXTERNAL_IP}:8080"
echo -e "  • ${BOLD}ArgoCD Web:${NC}    http://${EXTERNAL_IP}:30751  (or https://${EXTERNAL_IP}:30752)"
echo -e "  • ${BOLD}Firewall Rule:${NC} ${GREEN}${FIREWALL_NAME}${NC} (Ports: 22, 80, 443, 8080, 30751, 30752, 50000, 30000-32767)"
echo -e "  • ${BOLD}Network Tags:${NC}  ${TARGET_TAGS}"

echo -e "\n${CYAN}${BOLD}🔑 Credentials Summary:${NC}"
echo -e "  ${BOLD}Jenkins Admin Password:${NC}"
echo -e "  ${GREEN}${JENKINS_PASSWORD:-"Run: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"}${NC}"

echo -e "\n  ${BOLD}ArgoCD Credentials:${NC}"
echo -e "  Username: ${BOLD}admin${NC}"
echo -e "  Password: ${GREEN}${ARGOCD_PASSWORD:-"Run: kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"}${NC}"

echo -e "\n${YELLOW}${BOLD}ArgoCD CLI Login Command:${NC}"
echo -e "  argocd login ${EXTERNAL_IP}:30751 --username admin --password \"${ARGOCD_PASSWORD}\" --insecure"

echo -e "\n${YELLOW}${BOLD}Docker Non-Root Access:${NC}"
echo -e "  Run ${BOLD}newgrp docker${NC} to run docker commands without sudo in your current terminal."
echo -e "==================================================================\n"
