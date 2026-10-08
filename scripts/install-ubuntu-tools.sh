#!/usr/bin/env bash
# ==============================================================================
# UBUNTU SETUP SCRIPT: DOCKER + MINIKUBE + KUBECTL + JENKINS
# Supported OS: Ubuntu 20.04 / 22.04 / 24.04 LTS (x86_64)
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
  DEVOPS STACK INSTALLER FOR UBUNTU
  Docker | Minikube | Kubectl | Jenkins (Java 17)
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

echo -e "${YELLOW}[*] Installing packages for user:${NC} ${BOLD}${REAL_USER}${NC}"

# ==============================================================================
# 1. System Update & Dependencies
# ==============================================================================
echo -e "\n${CYAN}[1/5] Updating apt repository and installing prerequisites...${NC}"
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
# 2. Install Docker CE
# ==============================================================================
echo -e "\n${CYAN}[2/5] Installing Docker Engine & Docker Compose...${NC}"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add non-root user to docker group
usermod -aG docker "$REAL_USER"
chmod 666 /var/run/docker.sock || true
echo -e "${GREEN}[✓] Docker installed successfully! (${NC}$(docker --version)${GREEN})${NC}"

# ==============================================================================
# 3. Install Kubectl
# ==============================================================================
echo -e "\n${CYAN}[3/5] Installing Kubectl...${NC}"
K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl

# Setup bash completion and alias for the real user
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
if ! grep -q "alias k=kubectl" "$USER_HOME/.bashrc" 2>/dev/null; then
    echo "alias k=kubectl" >> "$USER_HOME/.bashrc"
    echo "complete -o default -F __start_kubectl k" >> "$USER_HOME/.bashrc"
    echo "source <(kubectl completion bash)" >> "$USER_HOME/.bashrc"
fi
echo -e "${GREEN}[✓] Kubectl installed: ${NC}$(kubectl version --client --output=yaml | grep gitVersion | head -n 1)"

# ==============================================================================
# 4. Install Minikube
# ==============================================================================
echo -e "\n${CYAN}[4/5] Installing Minikube...${NC}"
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
rm -f minikube-linux-amd64
echo -e "${GREEN}[✓] Minikube installed: ${NC}$(minikube version --short)"

# Start minikube as the non-root user using docker driver
echo -e "${YELLOW}[*] Starting Minikube cluster with Docker driver (takes ~1-2 min)...${NC}"
sudo -u "$REAL_USER" minikube config set driver docker
sudo -u "$REAL_USER" minikube start --driver=docker || {
    echo -e "${YELLOW}[!] Minikube start can be completed later by running: minikube start --driver=docker${NC}"
}

# ==============================================================================
# 5. Install Jenkins & Java 17
# ==============================================================================
echo -e "\n${CYAN}[5/5] Installing Java 17 OpenJDK & Jenkins...${NC}"
apt-get install -y fontconfig openjdk-17-jre openjdk-17-jdk

# Jenkins official keyring and repo
wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update -y
apt-get install -y jenkins

# Ensure Jenkins user can access docker socket
usermod -aG docker jenkins || true

systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins

echo -e "${GREEN}[✓] Jenkins service started on port 8080!${NC}"

# Wait briefly for Jenkins to initialize and generate admin password
echo -e "${YELLOW}[*] Waiting for Jenkins to generate initial admin password...${NC}"
sleep 15

# ==============================================================================
# Summary & Next Steps
# ==============================================================================
EXTERNAL_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD} ✓ INSTALLATION COMPLETE!                                         ${NC}"
echo -e "${GREEN}${BOLD}==================================================================${NC}"
echo -e "  • ${BOLD}Docker:${NC}     $(docker --version)"
echo -e "  • ${BOLD}Kubectl:${NC}    $(kubectl version --client --output=yaml | grep gitVersion | head -n 1 | awk '{print $2}')"
echo -e "  • ${BOLD}Minikube:${NC}   $(minikube version --short)"
echo -e "  • ${BOLD}Jenkins URL:${NC} http://${EXTERNAL_IP}:8080"
echo -e "\n${CYAN}${BOLD}Jenkins Initial Admin Password:${NC}"
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    echo -e "${BOLD}$(cat /var/lib/jenkins/secrets/initialAdminPassword)${NC}"
else
    echo -e "Run once Jenkins completes booting: ${BOLD}sudo cat /var/lib/jenkins/secrets/initialAdminPassword${NC}"
fi

echo -e "\n${YELLOW}${BOLD}Note on Docker permissions:${NC}"
echo -e "Run ${BOLD}newgrp docker${NC} or log out and log back in to use docker commands without sudo."
echo -e "==================================================================\n"
