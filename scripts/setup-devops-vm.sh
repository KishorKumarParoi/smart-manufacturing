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

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")

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

GIT_USER_NAME="${GIT_USER_NAME:-Kishor Kumar Paroi}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-1703053@student.ruet.ac.bd}"
GITHUB_USERNAME="${GITHUB_USERNAME:-KishorKumarParoi}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-kishorkumarparoi}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"

log_step() {
    echo -e "\n${CYAN}${BOLD}[STEP] $1${NC}"
}

log_success() {
    echo -e "${GREEN}${BOLD}[✓] $1${NC}"
}

# 1. Update and base packages
log_step "1/12: Updating system packages and installing baseline utilities..."
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
    lsb-release \
    acl \
    procps

# Configure Git & GitHub on host
log_step "2/12: Configuring Git identity & GitHub CLI for ${GITHUB_USERNAME}..."
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global init.defaultBranch main
git config --global credential.helper store
sudo -u "$REAL_USER" git config --global user.name "$GIT_USER_NAME" 2>/dev/null || true
sudo -u "$REAL_USER" git config --global user.email "$GIT_USER_EMAIL" 2>/dev/null || true
sudo -u "$REAL_USER" git config --global init.defaultBranch main 2>/dev/null || true
sudo -u "$REAL_USER" git config --global credential.helper store 2>/dev/null || true

# Install GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update -y && sudo apt-get install -y gh
fi

# Configure SSH key for GitHub
SSH_DIR="$USER_HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
if [ ! -f "$SSH_DIR/id_ed25519" ] && [ ! -f "$SSH_DIR/id_rsa" ]; then
    sudo -u "$REAL_USER" ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -f "$SSH_DIR/id_ed25519" -N "" 2>/dev/null || true
fi
touch "$SSH_DIR/known_hosts"
if ! grep -q "github.com" "$SSH_DIR/known_hosts" 2>/dev/null; then
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$SSH_DIR/known_hosts" 2>/dev/null || true
fi

# Store Git credentials if GITHUB_TOKEN is available
if [ -n "$GITHUB_TOKEN" ]; then
    CRED_ENTRY="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com"
    echo "$CRED_ENTRY" > "$USER_HOME/.git-credentials"
    chmod 600 "$USER_HOME/.git-credentials"
    echo "$CRED_ENTRY" > /root/.git-credentials
    chmod 600 /root/.git-credentials
    echo "$GITHUB_TOKEN" | sudo -u "$REAL_USER" gh auth login --with-token 2>/dev/null || true
    sudo -u "$REAL_USER" gh auth setup-git 2>/dev/null || true
fi
log_success "Git & GitHub configured (${GIT_USER_NAME} <${GIT_USER_EMAIL}>)!"

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
sudo usermod -aG docker "$REAL_USER"

# Configure permanent non-root Docker socket permissions (mode 0666 - NO 'newgrp docker' required)
sudo mkdir -p /etc/systemd/system/docker.socket.d
cat << "EOF_DOCKER_SOCK" | sudo tee /etc/systemd/system/docker.socket.d/override.conf >/dev/null
[Socket]
SocketMode=0666
EOF_DOCKER_SOCK

sudo mkdir -p /etc/systemd/system/docker.service.d
cat << "EOF_DOCKER_SVC" | sudo tee /etc/systemd/system/docker.service.d/override.conf >/dev/null
[Service]
ExecStartPost=/bin/sh -c 'chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true'
EOF_DOCKER_SVC

sudo mkdir -p /etc/tmpfiles.d
cat << "EOF_TMPFILES" | sudo tee /etc/tmpfiles.d/docker.conf >/dev/null
z /var/run/docker.sock 0666 root docker -
z /run/docker.sock 0666 root docker -
EOF_TMPFILES

sudo mkdir -p /etc/udev/rules.d
echo 'KERNEL=="docker.sock", MODE="0666"' | sudo tee /etc/udev/rules.d/80-docker.rules >/dev/null

sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl restart docker.socket >/dev/null 2>&1 || true
sudo chmod 666 /var/run/docker.sock /run/docker.sock 2>/dev/null || true
if command -v setfacl >/dev/null 2>&1; then
    sudo setfacl -m u:"$REAL_USER":rw /var/run/docker.sock 2>/dev/null || true
    sudo setfacl -m u:"$REAL_USER":rw /run/docker.sock 2>/dev/null || true
fi
log_success "Docker installed with permanent non-root access (no newgrp needed)!"

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

# 7. Deploy Jenkins (Docker)
log_step "7/12: Deploying Jenkins with Docker CLI integration, direct login, and Git/GitHub setup on port 8080..."
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

# GitHub & DockerHub Credentials for Jenkins Pipelines
cat << EOF_GROOVY_CREDS | sudo tee /var/jenkins_home/init.groovy.d/02-credentials.groovy >/dev/null
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

try {
    def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0]?.getStore()
    if (store != null) {
        def domain = Domain.global()

        // 1. GitHub credentials: github-token
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
            println "--> [DevOps Bootstrap] 'github-token' & 'github-pat' registered."
        }

        // 2. DockerHub credentials: dockerhub-token & gitops-dockerhub-token
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
            println "--> [DevOps Bootstrap] 'dockerhub-token' & 'gitops-dockerhub-token' registered."
        }
    }
} catch (Throwable t) {
    println "--> [DevOps Bootstrap] Credentials note: " + t.message
}
EOF_GROOVY_CREDS

# Automated Pipeline Job Creation in Jenkins
cat << 'EOF_GROOVY_JOB' | sudo tee /var/jenkins_home/init.groovy.d/03-create-pipeline-job.groovy >/dev/null
import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.*
import org.jenkinsci.plugins.workflow.cps.*
import hudson.plugins.git.*

def jobName = "smart-manufacturing-pipeline"
def repoUrl = "https://github.com/KishorKumarParoi/smart-manufacturing.git"
def instance = Jenkins.getInstance()

try {
    def job = instance.getItem(jobName)
    if (job == null) {
        job = instance.createProject(WorkflowJob, jobName)
        println "--> [DevOps Bootstrap] Created Pipeline job '${jobName}'"
    }
    def scm = new GitSCM(repoUrl)
    scm.branches = [new BranchSpec("*/main")]
    scm.userRemoteConfigs = [new UserRemoteConfig(repoUrl, null, null, "github-token")]
    def flowDef = new CpsScmFlowDefinition(scm, "Jenkinsfile")
    flowDef.setLightweight(true)
    job.setDefinition(flowDef)
    job.save()
    println "--> [DevOps Bootstrap] Pipeline job '${jobName}' configured with Git SCM & Jenkinsfile."
} catch (Throwable t) {
    println "--> [DevOps Bootstrap] Job configuration note: " + t.message
}
EOF_GROOVY_JOB

# Configure Git config & credentials inside Jenkins home
cat << EOF_GIT | sudo tee /var/jenkins_home/.gitconfig >/dev/null
[user]
	name = ${GIT_USER_NAME}
	email = ${GIT_USER_EMAIL}
[credential]
	helper = store
EOF_GIT

if [ -n "$GITHUB_TOKEN" ]; then
    echo "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com" | sudo tee /var/jenkins_home/.git-credentials >/dev/null
    sudo chmod 600 /var/jenkins_home/.git-credentials
fi

# Sync SSH keys into Jenkins home
sudo mkdir -p /var/jenkins_home/.ssh
if [ -f "$SSH_DIR/id_ed25519" ]; then
    sudo cp "$SSH_DIR/id_ed25519" /var/jenkins_home/.ssh/id_ed25519 2>/dev/null || true
    sudo cp "$SSH_DIR/id_ed25519.pub" /var/jenkins_home/.ssh/id_ed25519.pub 2>/dev/null || true
fi
if [ -f "$SSH_DIR/known_hosts" ]; then
    sudo cp "$SSH_DIR/known_hosts" /var/jenkins_home/.ssh/known_hosts 2>/dev/null || true
fi
sudo chmod 700 /var/jenkins_home/.ssh 2>/dev/null || true
sudo chown -R 1000:1000 /var/jenkins_home/.ssh /var/jenkins_home/.gitconfig /var/jenkins_home/.git-credentials /var/jenkins_home/init.groovy.d 2>/dev/null || true
sudo chmod -R 777 /var/jenkins_home

if docker ps -q -f name=^jenkins$ | grep -q .; then
    docker cp /var/jenkins_home/init.groovy.d/02-credentials.groovy jenkins:/var/jenkins_home/init.groovy.d/ 2>/dev/null || true
    docker cp /var/jenkins_home/init.groovy.d/03-create-pipeline-job.groovy jenkins:/var/jenkins_home/init.groovy.d/ 2>/dev/null || true
    docker cp /var/jenkins_home/.gitconfig jenkins:/var/jenkins_home/.gitconfig 2>/dev/null || true
    if [ -n "$GITHUB_TOKEN" ]; then
        docker cp /var/jenkins_home/.git-credentials jenkins:/var/jenkins_home/.git-credentials 2>/dev/null || true
    fi
    docker cp /var/jenkins_home/.ssh/. jenkins:/var/jenkins_home/.ssh/ 2>/dev/null || true
    docker exec -u root jenkins chown -R 1000:1000 /var/jenkins_home/.ssh /var/jenkins_home/.gitconfig /var/jenkins_home/.git-credentials /var/jenkins_home/init.groovy.d 2>/dev/null || true
    log_success "Jenkins container is running and Git/DockerHub credentials synced!"
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
      -e JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER}" \
      -e JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD}" \
      -e GITHUB_USERNAME="${GITHUB_USERNAME}" \
      -e GITHUB_TOKEN="${GITHUB_TOKEN}" \
      -e DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME}" \
      -e DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN}" \
      jenkins/jenkins:lts
    log_success "Jenkins container started on port 8080 (Login: ${JENKINS_ADMIN_USER} / ${JENKINS_ADMIN_PASSWORD})!"
fi

# Ensure Jenkins plugins (Docker, Docker Pipeline, Kubernetes, Git, Pipelines)
PLUGINS_TO_INSTALL=(docker-workflow docker-plugin kubernetes kubernetes-cli git workflow-aggregator pipeline-stage-view credentials-binding plain-credentials ws-cleanup)
NEED_INSTALL=false
for p in "${PLUGINS_TO_INSTALL[@]}"; do
    if [ ! -f "/var/jenkins_home/plugins/${p}.jpi" ] && [ ! -f "/var/jenkins_home/plugins/${p}.hpi" ]; then
        NEED_INSTALL=true
        break
    fi
done

if [ "$NEED_INSTALL" = "true" ]; then
    docker exec -u root jenkins jenkins-plugin-cli --plugins "${PLUGINS_TO_INSTALL[@]}" || true
    docker restart jenkins >/dev/null 2>&1 || true
    sleep 5
fi

# Authenticate Docker daemon inside Jenkins container
if [ -n "$DOCKERHUB_TOKEN" ] && [ -n "$DOCKERHUB_USERNAME" ]; then
    docker exec -u root jenkins bash -c "echo '$DOCKERHUB_TOKEN' | docker login -u '$DOCKERHUB_USERNAME' --password-stdin 2>/dev/null || true"
fi

# 8. Deploy SonarQube (Docker)
log_step "8/12: Deploying SonarQube Community Edition on port 9000..."
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

# 9. Deploy Sonatype Nexus 3 (Docker)
log_step "9/12: Deploying Sonatype Nexus Repository Manager on port 8081..."
sudo mkdir -p /var/nexus-data
sudo chown -R 200:200 /var/nexus-data
docker run -d \
  --name nexus \
  --restart always \
  -p 8081:8081 \
  -v /var/nexus-data:/nexus-data \
  sonatype/nexus3:latest
log_success "Nexus container started on port 8081!"

# 10. Deploy ArgoCD on Kubernetes
log_step "10/12: Deploying ArgoCD in Kubernetes & exposing via NodePort (Port 30080)..."
kubectl create namespace argocd || true
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Patch ArgoCD server to NodePort 30080 for web access
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30080}]}}'

# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
log_success "ArgoCD deployed in Kubernetes and accessible at NodePort 30080!"

# 11. Install CircleCI CLI
log_step "11/12: Installing CircleCI CLI & Runner toolchain..."
curl -fLSs https://raw.githubusercontent.com/CircleCI-Public/circleci-cli/master/install.sh | sudo bash
log_success "CircleCI CLI installed ($(circleci version))"

# 12. Configure Firewall Rules (GCP "allow-devops-platform" & UFW)
log_step "12/12: Applying automatic firewall rules ('allow-devops-platform')..."
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

# 13. System RAM Cleanup, Bloatware Purge & Performance Tuning
log_step "13/13: Flushing RAM, purging bloatware/cache, and accelerating performance..."
BLOAT_SERVICES=(whoopsie apport apport-autoreport unattended-upgrades update-notifier-download update-notifier-motd)
for svc in "${BLOAT_SERVICES[@]}"; do
    if sudo systemctl is-active --quiet "$svc" 2>/dev/null; then
        sudo systemctl stop "$svc" 2>/dev/null || true
    fi
    sudo systemctl disable "$svc" 2>/dev/null || true
    sudo systemctl mask "$svc" 2>/dev/null || true
done

export DEBIAN_FRONTEND=noninteractive
sudo rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
sudo apt-get autoremove --purge -y >/dev/null 2>&1 || true
sudo apt-get autoclean -y >/dev/null 2>&1 || true
sudo apt-get clean -y >/dev/null 2>&1 || true

if command -v journalctl >/dev/null 2>&1; then
    sudo journalctl --vacuum-time=1d --vacuum-size=50M >/dev/null 2>&1 || true
fi
sudo find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" -o -name "*.xz" \) -delete 2>/dev/null || true
sudo find /tmp -mindepth 1 -maxdepth 2 -not -name ".*" -not -name "hsperfdata_*" -mtime +1 -delete 2>/dev/null || true
sudo rm -rf /root/.cache/pip /home/*/.cache/pip /tmp/pip* /tmp/*.whl 2>/dev/null || true

sudo docker builder prune -f >/dev/null 2>&1 || true
sudo docker network prune -f >/dev/null 2>&1 || true
sudo docker image prune -f >/dev/null 2>&1 || true

sudo mkdir -p /etc/sysctl.d
cat << "EOF_SYSCTL" | sudo tee /etc/sysctl.d/99-devops-performance.conf >/dev/null
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
EOF_SYSCTL
sudo sysctl --system >/dev/null 2>&1 || true

sync
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
echo 1 | sudo tee /proc/sys/vm/compact_memory >/dev/null 2>&1 || true
if [ -f /proc/swaps ] && [ "$(wc -l < /proc/swaps 2>/dev/null || echo 0)" -gt 1 ]; then
    sudo swapoff -a 2>/dev/null && sudo swapon -a 2>/dev/null || true
fi
log_success "RAM freed and system performance accelerated!"

# Display Summary
echo -e "\n${GREEN}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD} ✓ ALL DEVOPS SERVICES DEPLOYED SUCCESSFULLY!                     ${NC}"
echo -e "${GREEN}${BOLD}==================================================================${NC}"
echo -e "Access the services via your VM's External IP:"
echo -e "  • ${BOLD}Docker:${NC}        $(docker --version) ${GREEN}[Non-root 0666 active]${NC}"
echo -e "  • ${BOLD}Jenkins:${NC}       http://<EXTERNAL_IP>:8080"
echo -e "  • ${BOLD}SonarQube:${NC}     http://<EXTERNAL_IP>:9000 (Default: admin / admin)"
echo -e "  • ${BOLD}Nexus:${NC}         http://<EXTERNAL_IP>:8081"
echo -e "  • ${BOLD}ArgoCD:${NC}        http://<EXTERNAL_IP>:30080  (or :30751)"
echo -e "  • ${BOLD}Firewall Rule:${NC} ${GREEN}${FIREWALL_NAME}${NC}"
echo -e "\n${CYAN}${BOLD}🔑 Credentials Summary:${NC}"
echo -e "  ${BOLD}Git Author:${NC}             ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
echo -e "  ${BOLD}GitHub Profile:${NC}         ${GREEN}${GITHUB_USERNAME}${NC}"
if [ -n "$GITHUB_TOKEN" ]; then
    echo -e "  ${BOLD}GitHub Token:${NC}           ${GREEN}[Configured in Git helper & Jenkins 'github-token']${NC}"
else
    echo -e "  ${BOLD}GitHub Token:${NC}           ${YELLOW}[Set via: export GITHUB_TOKEN=ghp_... and re-run]${NC}"
fi
if [ -f "$USER_HOME/.ssh/id_ed25519.pub" ]; then
    echo -e "  ${BOLD}SSH Public Key:${NC}         ${USER_HOME}/.ssh/id_ed25519.pub"
fi
echo -e "  ${BOLD}Jenkins Login:${NC}          ${JENKINS_ADMIN_USER} / ${JENKINS_ADMIN_PASSWORD}"
echo -e "  ${BOLD}Jenkins Admin Secret:${NC}   sudo cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true"
echo -e "  ${BOLD}Nexus Admin Password:${NC}   sudo cat /var/nexus-data/admin.password 2>/dev/null || true"
echo -e "  ${BOLD}ArgoCD Admin Password:${NC}  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d 2>/dev/null && echo"
echo -e "==================================================================\n"
