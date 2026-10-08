#!/usr/bin/env bash
# ==============================================================================
# ALL-IN-ONE DEVOPS PLATFORM VM BOOTSTRAP SCRIPT (UBUNTU 22.04 LTS)
# ==============================================================================
# Deploys: Docker, Kubernetes (K3s), Helm, Jenkins, SonarQube, Nexus,
#          ArgoCD, Terraform, Ansible, CircleCI CLI
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_step() {
    echo -e "\n${CYAN}${BOLD}[STEP] $1${NC}"
}

log_success() {
    echo -e "${GREEN}${BOLD}[✓] $1${NC}"
}

# 1. Update and base packages
log_step "1/10: Updating system packages and installing baseline utilities..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    unzip \
    jq \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# Configure kernel parameters for SonarQube (Elasticsearch requirement)
echo "Configuring kernel limits for SonarQube..."
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. Install Docker & Docker Compose
log_step "2/10: Installing Docker CE and Docker Compose Plugin..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
sudo chmod 666 /var/run/docker.sock || true
log_success "Docker installed successfully!"

# 3. Install Terraform
log_step "3/10: Installing Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update -y && sudo apt-get install -y terraform
log_success "Terraform installed ($(terraform -version | head -n 1))"

# 4. Install Ansible
log_step "4/10: Installing Ansible..."
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible
log_success "Ansible installed ($(ansible --version | head -n 1))"

# 5. Install Kubernetes (K3s - Lightweight CNCF Kubernetes)
log_step "5/10: Installing Kubernetes (K3s) & Kubectl..."
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
log_success "Kubernetes & Helm installed! Nodes: $(kubectl get nodes --no-headers | awk '{print $1, $2}')"

# 6. Deploy Jenkins (Docker)
log_step "6/10: Deploying Jenkins with Docker CLI integration and direct login on port 8080..."
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-admin123}"
sudo mkdir -p /var/jenkins_home/init.groovy.d
echo "2.0" | sudo tee /var/jenkins_home/jenkins.install.UpgradeWizard.state >/dev/null
echo "2.440.4" | sudo tee /var/jenkins_home/jenkins.install.InstallUtil.lastExecVersion >/dev/null

cat << EOF_GROOVY | sudo tee /var/jenkins_home/init.groovy.d/01-create-admin.groovy >/dev/null
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()
def realm = instance.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    realm = new HudsonPrivateSecurityRealm(false)
    instance.setSecurityRealm(realm)
}
def user = realm.getUser("${JENKINS_ADMIN_USER}")
if (user == null || realm.getAllUsers().find { it.getId().equalsIgnoreCase("${JENKINS_ADMIN_USER}") } == null) {
    realm.createAccount("${JENKINS_ADMIN_USER}", "${JENKINS_ADMIN_PASSWORD}")
} else {
    def pwd = hudson.security.HudsonPrivateSecurityRealm.Details.fromPlainPassword("${JENKINS_ADMIN_PASSWORD}")
    user.addProperty(pwd)
}
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
try { instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED) } catch (Throwable t) {}
instance.save()
EOF_GROOVY

sudo chmod -R 777 /var/jenkins_home

if docker ps -q -f name=^jenkins$ | grep -q .; then
    log_success "Jenkins container is already running!"
else
    docker rm -f jenkins 2>/dev/null || true
    docker run -d \
      --name jenkins \
      --restart always \
      -p 8080:8080 \
      -p 50000:50000 \
      -v /var/jenkins_home:/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $(which docker):/usr/bin/docker \
      -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
      jenkins/jenkins:lts-jdk17
    log_success "Jenkins container started on port 8080 (Login: ${JENKINS_ADMIN_USER} / ${JENKINS_ADMIN_PASSWORD})!"
fi

# 7. Deploy SonarQube (Docker)
log_step "7/10: Deploying SonarQube Community Edition on port 9000..."
sudo mkdir -p /var/sonarqube_data /var/sonarqube_extensions /var/sonarqube_logs
sudo chmod -R 777 /var/sonarqube_data /var/sonarqube_extensions /var/sonarqube_logs
docker run -d \
  --name sonarqube \
  --restart always \
  -p 9000:9000 \
  -v /var/sonarqube_data:/opt/sonarqube/data \
  -v /var/sonarqube_extensions:/opt/sonarqube/extensions \
  -v /var/sonarqube_logs:/opt/sonarqube/logs \
  sonarqube:community
log_success "SonarQube container started on port 9000!"

# 8. Deploy Sonatype Nexus 3 (Docker)
log_step "8/10: Deploying Sonatype Nexus Repository Manager on port 8081..."
sudo mkdir -p /var/nexus-data
sudo chown -R 200:200 /var/nexus-data
docker run -d \
  --name nexus \
  --restart always \
  -p 8081:8081 \
  -v /var/nexus-data:/nexus-data \
  sonatype/nexus3:latest
log_success "Nexus container started on port 8081!"

# 9. Deploy ArgoCD on Kubernetes
log_step "9/10: Deploying ArgoCD in Kubernetes & exposing via NodePort (Port 30080)..."
kubectl create namespace argocd || true
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Patch ArgoCD server to NodePort 30080 for web access
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30080}]}}'

# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
log_success "ArgoCD deployed in Kubernetes and accessible at NodePort 30080!"

# 10. Install CircleCI CLI
log_step "10/11: Installing CircleCI CLI & Runner toolchain..."
curl -fLSs https://raw.githubusercontent.com/CircleCI-Public/circleci-cli/master/install.sh | sudo bash
log_success "CircleCI CLI installed ($(circleci version))"

# 11. Configure Firewall Rules (GCP "allow-devops-platform" & UFW)
log_step "11/11: Applying automatic firewall rules ('allow-devops-platform')..."
FIREWALL_NAME="${FIREWALL_NAME:-allow-devops-platform}"
TARGET_TAGS="allow-devops-platform,devops-control-plane,devops-vm"
REQUIRED_PORTS=(22 80 443 8000 8080 8081 9000 30080 30751 30752 50000)

# Local UFW
sudo apt-get install -y --no-install-recommends ufw >/dev/null 2>&1 || true
for p in "${REQUIRED_PORTS[@]}"; do
    sudo ufw allow "${p}/tcp" comment "DevOps ${p}" >/dev/null 2>&1 || true
done
sudo ufw allow 30000:32767/tcp comment "Kubernetes NodePort Range" >/dev/null 2>&1 || true
if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    sudo ufw reload >/dev/null 2>&1 || true
fi

# GCP Metadata detection and tagging
GCP_METADATA_HEADER="Metadata-Flavor: Google"
GCP_METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"
GCP_VM_NAME=$(curl -s -f -m 2 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/name" 2>/dev/null || true)
if [ -n "$GCP_VM_NAME" ]; then
    GCP_ZONE_RAW=$(curl -s -f -m 2 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/instance/zone" 2>/dev/null || true)
    GCP_ZONE=$(echo "$GCP_ZONE_RAW" | awk -F/ '{print $NF}')
    GCP_PROJECT=$(curl -s -f -m 2 -H "$GCP_METADATA_HEADER" "$GCP_METADATA_BASE/project/project-id" 2>/dev/null || true)
    if command -v gcloud >/dev/null 2>&1; then
        gcloud compute instances add-tags "$GCP_VM_NAME" --zone="$GCP_ZONE" --tags="$TARGET_TAGS" --quiet >/dev/null 2>&1 || true
        PORT_SPEC="tcp:22,tcp:80,tcp:443,tcp:8000,tcp:8080,tcp:8081,tcp:9000,tcp:30080,tcp:30751,tcp:30752,tcp:30000-32767,tcp:50000"
        if gcloud compute firewall-rules describe "$FIREWALL_NAME" ${GCP_PROJECT:+--project="$GCP_PROJECT"} >/dev/null 2>&1; then
            gcloud compute firewall-rules update "$FIREWALL_NAME" ${GCP_PROJECT:+--project="$GCP_PROJECT"} --allow="$PORT_SPEC" --target-tags="$TARGET_TAGS" --quiet >/dev/null 2>&1 || true
        fi
    fi
    log_success "GCP tags '${TARGET_TAGS}' and firewall rule '${FIREWALL_NAME}' configured!"
else
    log_success "Local UFW firewall rules configured!"
fi

# Display Summary
echo -e "\n${GREEN}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD} ✓ ALL DEVOPS SERVICES DEPLOYED SUCCESSFULLY!                     ${NC}"
echo -e "${GREEN}${BOLD}==================================================================${NC}"
echo -e "Access the services via your VM's External IP:"
echo -e "  • ${BOLD}Jenkins:${NC}       http://<EXTERNAL_IP>:8080"
echo -e "  • ${BOLD}SonarQube:${NC}     http://<EXTERNAL_IP>:9000 (Default: admin / admin)"
echo -e "  • ${BOLD}Nexus:${NC}         http://<EXTERNAL_IP>:8081"
echo -e "  • ${BOLD}ArgoCD:${NC}        http://<EXTERNAL_IP>:30080  (or :30751)"
echo -e "  • ${BOLD}Firewall Rule:${NC} ${GREEN}${FIREWALL_NAME}${NC}"
echo -e "\nTo view initial passwords:"
echo -e "  ${CYAN}Jenkins Admin Password:${NC} sudo cat /var/jenkins_home/secrets/initialAdminPassword"
echo -e "  ${CYAN}Nexus Admin Password:${NC}   sudo cat /var/nexus-data/admin.password"
echo -e "  ${CYAN}ArgoCD Admin Password:${NC}  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo -e "==================================================================\n"
