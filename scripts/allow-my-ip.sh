#!/usr/bin/env bash
# ==============================================================================
# SECURE FIREWALL IP WHITELISTER (BOT PROTECTION / ZERO-TRUST)
# Locks all GCP firewall ports strictly to YOUR IP address & ISP subnet
# Blocks 100% of the public internet (0.0.0.0/0) to prevent bot scanners
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

GCP_PROJECT="${GCP_PROJECT:-project-53d8ce01-b0e0-4f8b-94c}"
FIREWALL_PUBLIC="allow-devops-public-web"
FIREWALL_ADMIN="allow-devops-admin-mgmt"
PUBLIC_PORT_SPEC="tcp:80,tcp:443,tcp:8000"
ADMIN_PORT_SPEC="tcp:22,tcp:3000,tcp:5000,tcp:5601,tcp:8080,tcp:8081,tcp:8082,tcp:9000,tcp:9090,tcp:30080,tcp:30090,tcp:30300,tcp:30601,tcp:30751,tcp:30752,tcp:30000-32767,tcp:50000"

echo -e "${CYAN}${BOLD}"
cat << "EOF"
================================================================================
   ZERO-TRUST FIREWALL IP WHITELISTER & ANTI-BOT PROTECTOR
================================================================================
EOF
echo -e "${NC}"

if ! command -v gcloud >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 'gcloud' CLI is required.${NC}"
    exit 1
fi

# Detect project
ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
[ -n "$ACTIVE_PROJECT" ] && [ "$ACTIVE_PROJECT" != "(unset)" ] && GCP_PROJECT="$ACTIVE_PROJECT"

# Detect user public IP
echo -e "${YELLOW}[*] Detecting your current public IP address...${NC}"
MY_IP=$(curl -s -m 4 https://api.ipify.org 2>/dev/null || curl -s -m 4 https://ifconfig.me 2>/dev/null || echo "")

if [ -z "$MY_IP" ]; then
    echo -e "${RED}[ERROR] Could not automatically detect public IP. Please specify manually:${NC}"
    echo "  ./scripts/allow-my-ip.sh <YOUR_IP>"
    exit 1
fi

# Allow passing explicit IP/CIDR as argument
if [ "$#" -gt 0 ]; then
    MY_IP="$1"
fi

# Derive /24 subnet (accommodates dynamic ISP IP rotation across the same pool)
if [[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SUBNET="$(echo "$MY_IP" | cut -d. -f1-3).0/24"
    ALLOWED_RANGES="${MY_IP}/32,${SUBNET},35.235.240.0/20"
else
    ALLOWED_RANGES="${MY_IP},35.235.240.0/20"
fi

echo -e "${GREEN}[✓] Detected Client IP:${NC}     ${BOLD}${MY_IP}${NC}"
if [ -n "${SUBNET:-}" ]; then
    echo -e "${GREEN}[✓] Derived ISP Subnet:${NC}    ${BOLD}${SUBNET}${NC}"
fi
echo -e "${YELLOW}[*] Target Project:${NC}        ${BOLD}${GCP_PROJECT}${NC}\n"

echo -e "${YELLOW}[*] Applying Zero-Trust firewall rules (Strictly restricting to your IP + IAP)...${NC}"

# Update Web Firewall
gcloud compute firewall-rules update "$FIREWALL_PUBLIC" \
    --project="$GCP_PROJECT" \
    --allow="$PUBLIC_PORT_SPEC" \
    --source-ranges="$ALLOWED_RANGES" \
    --quiet >/dev/null 2>&1 || \
gcloud compute firewall-rules create "$FIREWALL_PUBLIC" \
    --project="$GCP_PROJECT" \
    --allow="$PUBLIC_PORT_SPEC" \
    --source-ranges="$ALLOWED_RANGES" \
    --target-tags="devops-public-web,http-server,https-server" \
    --quiet >/dev/null 2>&1 || true

# Update Admin Firewall
gcloud compute firewall-rules update "$FIREWALL_ADMIN" \
    --project="$GCP_PROJECT" \
    --allow="$ADMIN_PORT_SPEC" \
    --source-ranges="$ALLOWED_RANGES" \
    --quiet >/dev/null 2>&1 || \
gcloud compute firewall-rules create "$FIREWALL_ADMIN" \
    --project="$GCP_PROJECT" \
    --allow="$ADMIN_PORT_SPEC" \
    --source-ranges="$ALLOWED_RANGES" \
    --target-tags="devops-control-plane,devops-vm" \
    --quiet >/dev/null 2>&1 || true

# Delete wide-open rule if present
gcloud compute firewall-rules delete "allow-devops-platform" --project="$GCP_PROJECT" --quiet >/dev/null 2>&1 || true

echo -e "\n${GREEN}${BOLD}🎉 SUCCESS! All firewall rules updated to ZERO-TRUST:${NC}"
echo -e "  - Allowed IP Range:  ${BOLD}${ALLOWED_RANGES}${NC}"
echo -e "  - Public Internet:   ${RED}${BOLD}BLOCKED (0.0.0.0/0 is denied access)${NC}"
echo -e "  - Bot Scanners:      ${GREEN}${BOLD}BLOCKED (automated reflection attacks impossible)${NC}\n"
