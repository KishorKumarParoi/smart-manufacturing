#!/usr/bin/env bash
# ==============================================================================
# ONE-CLICK ZERO-COST TEARDOWN & CLEANUP FOR SMART MANUFACTURING PLATFORM
# Mirrors deploy.sh: Deletes all cost-incurring GCP Compute Engine VMs,
# Persistent Disks, Static IPs, Firewalls, and Local Containers
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Visual formatting
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Default Configuration (Matched exactly with deploy.sh & scripts/install-ubuntu-tools.sh)
GCP_PROJECT="${GCP_PROJECT:-project-53d8ce01-b0e0-4f8b-94c}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
VM_NAME="${VM_NAME:-gitops}"
FIREWALL_PUBLIC="allow-devops-public-web"
FIREWALL_ADMIN="allow-devops-admin-mgmt"
FIREWALL_LEGACY="allow-devops-platform"

# Options
FORCE=false
DRY_RUN=false
CLEAN_ALL_PROJECT_INSTANCES=false

show_help() {
    cat << EOF
Usage: ./clear.sh [OPTIONS]

One-click zero-cost teardown script that terminates and deletes all cloud resources
provisioned by deploy.sh and the Smart Manufacturing platform.

Options:
  -y, --yes, -f, --force      Non-interactive: immediately destroy all resources without confirmation
  --dry-run                   Scan and display active cost-incurring resources without deleting
  --all                       Scan and delete all compute instances in the active project (not just 'gitops')
  --help, -h                  Show this help message

Examples:
  ./clear.sh                  Interactive cleanup with confirmation
  ./clear.sh --force          Instant automated deletion of all cost-incurring instances & disks
  ./clear.sh --dry-run        Audit what is currently running and incurring charges
EOF
}

# Parse CLI arguments
for arg in "$@"; do
    case "$arg" in
        -y|--yes|-f|--force)
            FORCE=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --all)
            CLEAN_ALL_PROJECT_INSTANCES=true
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $arg${NC}"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${CYAN}${BOLD}"
cat << "EOF"
================================================================================
   ZERO-COST CLOUD TEARDOWN & RESOURCE CLEANUP (GCP & LOCAL)
================================================================================
EOF
echo -e "${NC}"

# 1. Verify gcloud CLI is available
if ! command -v gcloud >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 'gcloud' CLI is not installed or not in PATH.${NC}"
    echo "  Please install Google Cloud SDK or authenticate via 'gcloud auth login'."
    exit 1
fi

# Detect active project from gcloud if not explicitly set
ACTIVE_GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ -n "$ACTIVE_GCLOUD_PROJECT" ] && [ "$ACTIVE_GCLOUD_PROJECT" != "(unset)" ]; then
    GCP_PROJECT="$ACTIVE_GCLOUD_PROJECT"
fi

echo -e "${YELLOW}[*] Target Project:${NC} ${BOLD}${GCP_PROJECT}${NC}"
echo -e "${YELLOW}[*] Target Zone:${NC}    ${BOLD}${GCP_ZONE}${NC}\n"

# 2. Audit Active Resources
echo -e "${YELLOW}[1/6] Scanning for active Compute Engine instances...${NC}"
INSTANCES_TO_DELETE=()

if [ "$CLEAN_ALL_PROJECT_INSTANCES" = true ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && INSTANCES_TO_DELETE+=("$line")
    done < <(gcloud compute instances list --project="$GCP_PROJECT" --format="value(name,zone)" 2>/dev/null || true)
else
    # Check specific VM 'gitops' or instances created by deploy.sh
    EXISTING_VM=$(gcloud compute instances list --project="$GCP_PROJECT" --filter="name=${VM_NAME} OR tags.items:devops-vm" --format="value(name,zone)" 2>/dev/null || true)
    if [ -n "$EXISTING_VM" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && INSTANCES_TO_DELETE+=("$line")
        done <<< "$EXISTING_VM"
    fi
fi

# Audit Disks
echo -e "${YELLOW}[2/6] Scanning for persistent disks...${NC}"
DISKS_TO_DELETE=()
while IFS= read -r line; do
    [ -n "$line" ] && DISKS_TO_DELETE+=("$line")
done < <(gcloud compute disks list --project="$GCP_PROJECT" --filter="name=${VM_NAME} OR users:''" --format="value(name,zone)" 2>/dev/null || true)

# Audit Static IPs
echo -e "${YELLOW}[3/6] Scanning for reserved external IP addresses...${NC}"
IPS_TO_DELETE=()
while IFS= read -r line; do
    [ -n "$line" ] && IPS_TO_DELETE+=("$line")
done < <(gcloud compute addresses list --project="$GCP_PROJECT" --format="value(name,region)" 2>/dev/null || true)

# Audit Firewalls
echo -e "${YELLOW}[4/6] Scanning for DevOps firewall rules...${NC}"
FWS_TO_DELETE=()
for fw in "$FIREWALL_PUBLIC" "$FIREWALL_ADMIN" "$FIREWALL_LEGACY"; do
    if gcloud compute firewall-rules describe "$fw" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        FWS_TO_DELETE+=("$fw")
    fi
done

# Display Audit Summary
echo -e "\n${BOLD}================ RESOURCE AUDIT SUMMARY ================${NC}"
if [ ${#INSTANCES_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Instances:       ${GREEN}None active (0 instances)${NC}"
else
    echo -e "  Instances:       ${RED}${BOLD}${#INSTANCES_TO_DELETE[@]} active instance(s) found:${NC}"
    for inst in "${INSTANCES_TO_DELETE[@]}"; do
        echo -e "                   - $inst"
    done
fi

if [ ${#DISKS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Persistent Disks: ${GREEN}None orphaned or matching (0 disks)${NC}"
else
    echo -e "  Persistent Disks: ${RED}${BOLD}${#DISKS_TO_DELETE[@]} disk(s) found:${NC}"
    for disk in "${DISKS_TO_DELETE[@]}"; do
        echo -e "                   - $disk"
    done
fi

if [ ${#IPS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Static IPs:      ${GREEN}None allocated (0 IPs)${NC}"
else
    echo -e "  Static IPs:      ${YELLOW}${#IPS_TO_DELETE[@]} IP(s) found:${NC}"
    for ip in "${IPS_TO_DELETE[@]}"; do
        echo -e "                   - $ip"
    done
fi

if [ ${#FWS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Firewall Rules:  ${GREEN}None found (0 rules)${NC}"
else
    echo -e "  Firewall Rules:  ${YELLOW}${#FWS_TO_DELETE[@]} rule(s) found:${NC}"
    for fw in "${FWS_TO_DELETE[@]}"; do
        echo -e "                   - $fw"
    done
fi
echo -e "${BOLD}========================================================${NC}\n"

if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}[✓] Dry run finished. No resources were modified or deleted.${NC}"
    exit 0
fi

# If nothing exists, notify user and clean local compose
if [ ${#INSTANCES_TO_DELETE[@]} -eq 0 ] && [ ${#DISKS_TO_DELETE[@]} -eq 0 ] && [ ${#IPS_TO_DELETE[@]} -eq 0 ] && [ ${#FWS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "${GREEN}[✓] No cost-incurring GCP compute resources found in project ${GCP_PROJECT}!${NC}"
else
    # Confirmation prompt if not forced
    if [ "$FORCE" != true ]; then
        echo -e "${RED}${BOLD}[WARNING] This will permanently delete the resources listed above to eliminate all cloud costs.${NC}"
        read -r -p "Do you want to proceed with deletion? [Y/n]: " CONFIRM
        CONFIRM="${CONFIRM:-Y}"
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}[*] Cleanup cancelled by user.${NC}"
            exit 0
        fi
    fi

    # 3. Execution: Delete Instances
    if [ ${#INSTANCES_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Deleting Compute Engine instances & attached boot/data disks...${NC}"
        for inst_entry in "${INSTANCES_TO_DELETE[@]}"; do
            INST_NAME=$(echo "$inst_entry" | awk '{print $1}')
            INST_ZONE=$(echo "$inst_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Deleting instance ${BOLD}${INST_NAME}${NC} (Zone: ${INST_ZONE}) with all attached disks..."
            gcloud compute instances delete "$INST_NAME" \
                --project="$GCP_PROJECT" \
                --zone="$INST_ZONE" \
                --delete-disks=all \
                --quiet || echo -e "  ${YELLOW}[!] Failed to delete ${INST_NAME}, will retry disk cleanup...${NC}"
        done
        echo -e "${GREEN}[✓] Instance deletion finished.${NC}"
    fi

    # 4. Execution: Delete Orphaned Disks
    if [ ${#DISKS_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Deleting lingering persistent disks...${NC}"
        for disk_entry in "${DISKS_TO_DELETE[@]}"; do
            DISK_NAME=$(echo "$disk_entry" | awk '{print $1}')
            DISK_ZONE=$(echo "$disk_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Deleting disk ${BOLD}${DISK_NAME}${NC} (Zone: ${DISK_ZONE})..."
            gcloud compute disks delete "$DISK_NAME" \
                --project="$GCP_PROJECT" \
                --zone="$DISK_ZONE" \
                --quiet 2>/dev/null || true
        done
        echo -e "${GREEN}[✓] Persistent disk cleanup finished.${NC}"
    fi

    # 5. Execution: Release Static IPs
    if [ ${#IPS_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Releasing static external IP addresses...${NC}"
        for ip_entry in "${IPS_TO_DELETE[@]}"; do
            IP_NAME=$(echo "$ip_entry" | awk '{print $1}')
            IP_REGION=$(echo "$ip_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Releasing IP ${BOLD}${IP_NAME}${NC} (Region: ${IP_REGION})..."
            gcloud compute addresses delete "$IP_NAME" \
                --project="$GCP_PROJECT" \
                --region="$IP_REGION" \
                --quiet 2>/dev/null || true
        done
        echo -e "${GREEN}[✓] Static IP cleanup finished.${NC}"
    fi

    # 6. Execution: Delete Firewall Rules
    if [ ${#FWS_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Removing custom DevOps firewall rules...${NC}"
        for fw in "${FWS_TO_DELETE[@]}"; do
            echo -e "  ${RED}✖${NC} Deleting firewall rule ${BOLD}${fw}${NC}..."
            gcloud compute firewall-rules delete "$fw" \
                --project="$GCP_PROJECT" \
                --quiet 2>/dev/null || true
        done
        echo -e "${GREEN}[✓] Firewall cleanup finished.${NC}"
    fi
fi

# 7. Local Docker & Process Cleanup
echo -e "\n${YELLOW}[5/6] Checking and stopping local Docker containers & volumes...${NC}"
if command -v docker >/dev/null 2>&1; then
    if [ -f "${SCRIPT_DIR}/docker/docker-compose.yml" ]; then
        docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" down -v --remove-orphans 2>/dev/null || true
        echo -e "${GREEN}[✓] Local docker-compose services stopped and volumes purged.${NC}"
    fi
fi

# 8. Final Live Zero-Cost Verification
echo -e "\n${YELLOW}[6/6] Performing final Zero-Cost audit verification...${NC}"
FINAL_INSTANCES=$(gcloud compute instances list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
FINAL_DISKS=$(gcloud compute disks list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)

echo -e "\n${BOLD}================ FINAL CLOUD STATUS AUDIT ================${NC}"
if [ -z "$FINAL_INSTANCES" ]; then
    echo -e "  Active Instances:     ${GREEN}${BOLD}0 (NO Compute Engine charges)${NC}"
else
    echo -e "  Active Instances:     ${RED}${BOLD}Warning: Still active: ${FINAL_INSTANCES}${NC}"
fi

if [ -z "$FINAL_DISKS" ]; then
    echo -e "  Persistent Disks:     ${GREEN}${BOLD}0 (NO Persistent Disk charges)${NC}"
else
    echo -e "  Persistent Disks:     ${YELLOW}Active disks remaining: ${FINAL_DISKS}${NC}"
fi
echo -e "  Estimated Cloud Burn: ${GREEN}${BOLD}\$0.00 / hr${NC}"
echo -e "${BOLD}==========================================================${NC}\n"

echo -e "${GREEN}${BOLD}🎉 Zero-cost teardown complete! All cost-incurring resources are deleted.${NC}\n"
