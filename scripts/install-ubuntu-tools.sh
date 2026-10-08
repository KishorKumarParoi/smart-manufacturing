#!/usr/bin/env bash
# ==============================================================================
# ALL-IN-ONE UBUNTU DEVOPS SETUP SCRIPT
# Docker | Minikube | Kubectl | ArgoCD CLI & Server | Jenkins (Containerized)
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
  Docker | Minikube | Kubectl | ArgoCD | Jenkins (in Minikube Network)
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
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

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
