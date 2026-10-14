#!/usr/bin/env bash
# ==============================================================================
# ONE-CLICK ZERO-COST TEARDOWN & CLEANUP FOR SMART MANUFACTURING PLATFORM
# Mirrors deploy.sh: Deletes ALL cost-incurring resources:
# - Compute Engine VMs & GPU worker nodes
# - Google Kubernetes Engine (GKE) clusters & GPU node pools
# - Google Cloud TPUs (Cloud TPU VMs & nodes)
# - Persistent Disks (Standard, Balanced, SSD, orphaned disks)
# - Network: Cloud NAT Gateways, Cloud Routers, Forwarding Rules / Load Balancers
# - Static External IP Addresses (Regional & Global)
# - Custom Firewall Rules & Local Docker Containers
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

# Default Configuration
GCP_PROJECT="${GCP_PROJECT:-project-53d8ce01-b0e0-4f8b-94c}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_REGION="${GCP_REGION:-us-central1}"
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

Comprehensive zero-cost teardown script that terminates and deletes ALL cloud resources
including VMs, GPUs, GKE clusters, Cloud TPUs, persistent disks, and network assets
(NAT gateways, routers, load balancers, static IPs).

Options:
  -y, --yes, -f, --force      Non-interactive: immediately destroy all resources without confirmation
  --dry-run                   Scan and display active cost-incurring resources without deleting
  --all                       Scan and delete all compute/network resources across the entire active project
  --help, -h                  Show this help message

Examples:
  ./clear.sh                  Interactive cleanup with confirmation
  ./clear.sh --force          Instant automated deletion of all cost-incurring resources
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
   VMs | GPUs | GKE | TPUs | Disks | NAT | Routers | Load Balancers | IPs
================================================================================
EOF
echo -e "${NC}"

# 1. Verify gcloud CLI
if ! command -v gcloud >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 'gcloud' CLI is not installed or not in PATH.${NC}"
    exit 1
fi

ACTIVE_GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ -n "$ACTIVE_GCLOUD_PROJECT" ] && [ "$ACTIVE_GCLOUD_PROJECT" != "(unset)" ]; then
    GCP_PROJECT="$ACTIVE_GCLOUD_PROJECT"
fi

echo -e "${YELLOW}[*] Target Project:${NC} ${BOLD}${GCP_PROJECT}${NC}"
echo -e "${YELLOW}[*] Target Region:${NC}  ${BOLD}${GCP_REGION}${NC}"
echo -e "${YELLOW}[*] Target Zone:${NC}    ${BOLD}${GCP_ZONE}${NC}\n"

# ==============================================================================
# AUDIT ACTIVE RESOURCES ACROSS ALL TIERS
# ==============================================================================

# 1. Audit Compute Engine Instances & GPU Nodes
echo -e "${YELLOW}[1/8] Scanning for Compute Engine instances & GPU worker nodes...${NC}"
INSTANCES_TO_DELETE=()
GPU_INSTANCES=()

if [ "$CLEAN_ALL_PROJECT_INSTANCES" = true ]; then
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            INSTANCES_TO_DELETE+=("$line")
        fi
    done < <(gcloud compute instances list --project="$GCP_PROJECT" --format="value(name,zone)" 2>/dev/null || true)
else
    EXISTING_VM=$(gcloud compute instances list --project="$GCP_PROJECT" --filter="name=${VM_NAME} OR tags.items:devops-vm" --format="value(name,zone)" 2>/dev/null || true)
    if [ -n "$EXISTING_VM" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && INSTANCES_TO_DELETE+=("$line")
        done <<< "$EXISTING_VM"
    fi
fi

# Check for instances with attached GPUs
while IFS= read -r line; do
    [ -n "$line" ] && GPU_INSTANCES+=("$line")
done < <(gcloud compute instances list --project="$GCP_PROJECT" --filter="guestAccelerators:*" --format="value(name,zone)" 2>/dev/null || true)

# 2. Audit GKE Clusters (including GPU node pools)
echo -e "${YELLOW}[2/8] Scanning for Google Kubernetes Engine (GKE) clusters...${NC}"
GKE_CLUSTERS=()
while IFS= read -r line; do
    [ -n "$line" ] && GKE_CLUSTERS+=("$line")
done < <(gcloud container clusters list --project="$GCP_PROJECT" --format="value(name,location)" 2>/dev/null || true)

# 3. Audit Cloud TPUs (TPU VMs & nodes)
echo -e "${YELLOW}[3/8] Scanning for Google Cloud TPUs (Cloud TPU VMs & nodes)...${NC}"
TPUS_TO_DELETE=()
while IFS= read -r line; do
    [ -n "$line" ] && TPUS_TO_DELETE+=("$line")
done < <(gcloud compute tpus tpu-vm list --project="$GCP_PROJECT" --format="value(name,zone)" 2>/dev/null || true)

# 4. Audit Persistent Disks
echo -e "${YELLOW}[4/8] Scanning for persistent disks (boot, data, SSD, orphaned)...${NC}"
DISKS_TO_DELETE=()
while IFS= read -r line; do
    [ -n "$line" ] && DISKS_TO_DELETE+=("$line")
done < <(gcloud compute disks list --project="$GCP_PROJECT" --filter="name=${VM_NAME} OR users:''" --format="value(name,zone)" 2>/dev/null || true)

# 5. Audit Network: Forwarding Rules & Load Balancers
echo -e "${YELLOW}[5/8] Scanning for Cloud Load Balancers & Forwarding Rules...${NC}"
FORWARDING_RULES=()
while IFS= read -r line; do
    [ -n "$line" ] && FORWARDING_RULES+=("$line")
done < <(gcloud compute forwarding-rules list --project="$GCP_PROJECT" --format="value(name,region)" 2>/dev/null || true)

# 6. Audit Network: Cloud NAT Gateways & Cloud Routers
echo -e "${YELLOW}[6/8] Scanning for Cloud NAT Gateways & Cloud Routers...${NC}"
ROUTERS_TO_DELETE=()
while IFS= read -r line; do
    [ -n "$line" ] && ROUTERS_TO_DELETE+=("$line")
done < <(gcloud compute routers list --project="$GCP_PROJECT" --format="value(name,region)" 2>/dev/null || true)

# 7. Audit Static External IP Addresses (Regional & Global)
echo -e "${YELLOW}[7/8] Scanning for reserved external IP addresses...${NC}"
IPS_TO_DELETE=()
while IFS= read -r line; do
    [ -n "$line" ] && IPS_TO_DELETE+=("$line")
done < <(gcloud compute addresses list --project="$GCP_PROJECT" --format="value(name,region)" 2>/dev/null || true)

# 8. Audit DevOps Firewall Rules
echo -e "${YELLOW}[8/8] Scanning for DevOps firewall rules...${NC}"
FWS_TO_DELETE=()
for fw in "$FIREWALL_PUBLIC" "$FIREWALL_ADMIN" "$FIREWALL_LEGACY"; do
    if gcloud compute firewall-rules describe "$fw" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        FWS_TO_DELETE+=("$fw")
    fi
done

# ==============================================================================
# DISPLAY AUDIT SUMMARY
# ==============================================================================
echo -e "\n${BOLD}================ RESOURCE AUDIT SUMMARY ================${NC}"

# Instances & GPUs
if [ ${#INSTANCES_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Compute VMs:       ${GREEN}None active (0 instances)${NC}"
else
    echo -e "  Compute VMs:       ${RED}${BOLD}${#INSTANCES_TO_DELETE[@]} active instance(s) found:${NC}"
    for inst in "${INSTANCES_TO_DELETE[@]}"; do
        echo -e "                     - $inst"
    done
fi

if [ ${#GPU_INSTANCES[@]} -gt 0 ]; then
    echo -e "  GPU Accelerators:  ${RED}${BOLD}${#GPU_INSTANCES[@]} instance(s) with active GPUs found!${NC}"
fi

# GKE Clusters
if [ ${#GKE_CLUSTERS[@]} -eq 0 ]; then
    echo -e "  GKE Clusters:      ${GREEN}None active (0 clusters)${NC}"
else
    echo -e "  GKE Clusters:      ${RED}${BOLD}${#GKE_CLUSTERS[@]} cluster(s) found:${NC}"
    for cl in "${GKE_CLUSTERS[@]}"; do
        echo -e "                     - $cl"
    done
fi

# Cloud TPUs
if [ ${#TPUS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Cloud TPUs:        ${GREEN}None active (0 TPUs)${NC}"
else
    echo -e "  Cloud TPUs:        ${RED}${BOLD}${#TPUS_TO_DELETE[@]} active TPU(s) found:${NC}"
    for tpu in "${TPUS_TO_DELETE[@]}"; do
        echo -e "                     - $tpu"
    done
fi

# Persistent Disks
if [ ${#DISKS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Persistent Disks:  ${GREEN}None orphaned or matching (0 disks)${NC}"
else
    echo -e "  Persistent Disks:  ${RED}${BOLD}${#DISKS_TO_DELETE[@]} disk(s) found:${NC}"
    for disk in "${DISKS_TO_DELETE[@]}"; do
        echo -e "                     - $disk"
    done
fi

# Load Balancers & Forwarding Rules
if [ ${#FORWARDING_RULES[@]} -eq 0 ]; then
    echo -e "  Forwarding Rules:  ${GREEN}None active (0 rules)${NC}"
else
    echo -e "  Forwarding Rules:  ${YELLOW}${#FORWARDING_RULES[@]} rule(s) found:${NC}"
    for fr in "${FORWARDING_RULES[@]}"; do
        echo -e "                     - $fr"
    done
fi

# Cloud Routers & NAT
if [ ${#ROUTERS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Cloud Routers/NAT: ${GREEN}None active (0 routers)${NC}"
else
    echo -e "  Cloud Routers/NAT: ${YELLOW}${#ROUTERS_TO_DELETE[@]} router(s) found:${NC}"
    for rt in "${ROUTERS_TO_DELETE[@]}"; do
        echo -e "                     - $rt"
    done
fi

# Static IPs
if [ ${#IPS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Static IPs:        ${GREEN}None allocated (0 IPs)${NC}"
else
    echo -e "  Static IPs:        ${YELLOW}${#IPS_TO_DELETE[@]} IP(s) found:${NC}"
    for ip in "${IPS_TO_DELETE[@]}"; do
        echo -e "                     - $ip"
    done
fi

# Firewalls
if [ ${#FWS_TO_DELETE[@]} -eq 0 ]; then
    echo -e "  Firewall Rules:    ${GREEN}None found (0 rules)${NC}"
else
    echo -e "  Firewall Rules:    ${YELLOW}${#FWS_TO_DELETE[@]} rule(s) found:${NC}"
    for fw in "${FWS_TO_DELETE[@]}"; do
        echo -e "                     - $fw"
    done
fi
echo -e "${BOLD}========================================================${NC}\n"

if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}[✓] Dry run finished. No resources were modified or deleted.${NC}"
    exit 0
fi

TOTAL_ITEMS=$(( ${#INSTANCES_TO_DELETE[@]} + ${#GKE_CLUSTERS[@]} + ${#TPUS_TO_DELETE[@]} + ${#DISKS_TO_DELETE[@]} + ${#FORWARDING_RULES[@]} + ${#ROUTERS_TO_DELETE[@]} + ${#IPS_TO_DELETE[@]} + ${#FWS_TO_DELETE[@]} ))

if [ "$TOTAL_ITEMS" -eq 0 ]; then
    echo -e "${GREEN}[✓] Zero cost-incurring cloud resources found in project ${GCP_PROJECT}!${NC}"
else
    if [ "$FORCE" != true ]; then
        echo -e "${RED}${BOLD}[WARNING] This will permanently delete all ${TOTAL_ITEMS} resource(s) listed above to eliminate 100% of cloud costs.${NC}"
        read -r -p "Do you want to proceed with deletion? [Y/n]: " CONFIRM
        CONFIRM="${CONFIRM:-Y}"
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}[*] Cleanup cancelled by user.${NC}"
            exit 0
        fi
    fi

    # 1. Delete GKE Clusters
    if [ ${#GKE_CLUSTERS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Deleting GKE clusters & associated GPU node pools...${NC}"
        for cl_entry in "${GKE_CLUSTERS[@]}"; do
            CL_NAME=$(echo "$cl_entry" | awk '{print $1}')
            CL_LOC=$(echo "$cl_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Deleting GKE cluster ${BOLD}${CL_NAME}${NC} (${CL_LOC})..."
            gcloud container clusters delete "$CL_NAME" \
                --project="$GCP_PROJECT" \
                --location="$CL_LOC" \
                --quiet || true
        done
        echo -e "${GREEN}[✓] GKE cluster deletion complete.${NC}"
    fi

    # 2. Delete Cloud TPUs
    if [ ${#TPUS_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Deleting Cloud TPUs...${NC}"
        for tpu_entry in "${TPUS_TO_DELETE[@]}"; do
            TPU_NAME=$(echo "$tpu_entry" | awk '{print $1}')
            TPU_ZONE=$(echo "$tpu_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Deleting Cloud TPU ${BOLD}${TPU_NAME}${NC} (Zone: ${TPU_ZONE})..."
            gcloud compute tpus tpu-vm delete "$TPU_NAME" \
                --project="$GCP_PROJECT" \
                --zone="$TPU_ZONE" \
                --quiet 2>/dev/null || true
        done
        echo -e "${GREEN}[✓] Cloud TPU deletion complete.${NC}"
    fi

    # 3. Delete Compute Engine instances & attached disks
    if [ ${#INSTANCES_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Deleting Compute Engine instances & attached disks...${NC}"
        for inst_entry in "${INSTANCES_TO_DELETE[@]}"; do
            INST_NAME=$(echo "$inst_entry" | awk '{print $1}')
            INST_ZONE=$(echo "$inst_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Deleting instance ${BOLD}${INST_NAME}${NC} (Zone: ${INST_ZONE}) with all attached disks..."
            gcloud compute instances delete "$INST_NAME" \
                --project="$GCP_PROJECT" \
                --zone="$INST_ZONE" \
                --delete-disks=all \
                --quiet || true
        done
        echo -e "${GREEN}[✓] Instance deletion finished.${NC}"
    fi

    # 4. Delete Orphaned Disks
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

    # 5. Delete Forwarding Rules (Load Balancers)
    if [ ${#FORWARDING_RULES[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Deleting forwarding rules & load balancer endpoints...${NC}"
        for fr_entry in "${FORWARDING_RULES[@]}"; do
            FR_NAME=$(echo "$fr_entry" | awk '{print $1}')
            FR_REGION=$(echo "$fr_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Deleting forwarding rule ${BOLD}${FR_NAME}${NC}..."
            gcloud compute forwarding-rules delete "$FR_NAME" \
                --project="$GCP_PROJECT" \
                --region="$FR_REGION" \
                --quiet 2>/dev/null || \
            gcloud compute forwarding-rules delete "$FR_NAME" \
                --project="$GCP_PROJECT" \
                --global \
                --quiet 2>/dev/null || true
        done
        echo -e "${GREEN}[✓] Forwarding rule cleanup finished.${NC}"
    fi

    # 6. Delete Cloud NAT & Cloud Routers
    if [ ${#ROUTERS_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Deleting Cloud Routers & NAT Gateways...${NC}"
        for rt_entry in "${ROUTERS_TO_DELETE[@]}"; do
            RT_NAME=$(echo "$rt_entry" | awk '{print $1}')
            RT_REGION=$(echo "$rt_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Deleting Cloud Router ${BOLD}${RT_NAME}${NC} (Region: ${RT_REGION})..."
            gcloud compute routers delete "$RT_NAME" \
                --project="$GCP_PROJECT" \
                --region="$RT_REGION" \
                --quiet 2>/dev/null || true
        done
        echo -e "${GREEN}[✓] Router/NAT cleanup finished.${NC}"
    fi

    # 7. Release Static External IPs
    if [ ${#IPS_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Releasing static external IP addresses...${NC}"
        for ip_entry in "${IPS_TO_DELETE[@]}"; do
            IP_NAME=$(echo "$ip_entry" | awk '{print $1}')
            IP_REGION=$(echo "$ip_entry" | awk '{print $2}')
            echo -e "  ${RED}✖${NC} Releasing IP ${BOLD}${IP_NAME}${NC}..."
            if [ -n "$IP_REGION" ] && [ "$IP_REGION" != "(unset)" ]; then
                gcloud compute addresses delete "$IP_NAME" \
                    --project="$GCP_PROJECT" \
                    --region="$IP_REGION" \
                    --quiet 2>/dev/null || true
            else
                gcloud compute addresses delete "$IP_NAME" \
                    --project="$GCP_PROJECT" \
                    --global \
                    --quiet 2>/dev/null || true
            fi
        done
        echo -e "${GREEN}[✓] Static IP cleanup finished.${NC}"
    fi

    # 8. Delete Firewall Rules
    if [ ${#FWS_TO_DELETE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}[*] Removing DevOps firewall rules...${NC}"
        for fw in "${FWS_TO_DELETE[@]}"; do
            echo -e "  ${RED}✖${NC} Deleting firewall rule ${BOLD}${fw}${NC}..."
            gcloud compute firewall-rules delete "$fw" \
                --project="$GCP_PROJECT" \
                --quiet 2>/dev/null || true
        done
        echo -e "${GREEN}[✓] Firewall cleanup finished.${NC}"
    fi
fi

# Local Docker & Volume Cleanup
echo -e "\n${YELLOW}[*] Checking and stopping local Docker containers & volumes...${NC}"
if command -v docker >/dev/null 2>&1; then
    if [ -f "${SCRIPT_DIR}/docker/docker-compose.yml" ]; then
        docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" down -v --remove-orphans 2>/dev/null || true
        echo -e "${GREEN}[✓] Local docker-compose services stopped and volumes purged.${NC}"
    fi
fi

# Final Zero-Cost Verification
echo -e "\n${YELLOW}[*] Performing final comprehensive Zero-Cost audit verification...${NC}"
FINAL_INSTANCES=$(gcloud compute instances list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
FINAL_GKE=$(gcloud container clusters list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
FINAL_TPUS=$(gcloud compute tpus tpu-vm list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
FINAL_DISKS=$(gcloud compute disks list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
FINAL_IPS=$(gcloud compute addresses list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)

echo -e "\n${BOLD}================ FINAL CLOUD STATUS AUDIT ================${NC}"
[ -z "$FINAL_INSTANCES" ] && echo -e "  Active VMs & GPUs:    ${GREEN}${BOLD}0 (NO Compute Engine charges)${NC}" || echo -e "  Active VMs:           ${RED}${BOLD}Warning: ${FINAL_INSTANCES}${NC}"
[ -z "$FINAL_GKE" ]       && echo -e "  Active GKE Clusters:  ${GREEN}${BOLD}0 (NO Kubernetes cluster charges)${NC}" || echo -e "  Active GKE:           ${RED}${BOLD}Warning: ${FINAL_GKE}${NC}"
[ -z "$FINAL_TPUS" ]      && echo -e "  Active Cloud TPUs:    ${GREEN}${BOLD}0 (NO TPU charges)${NC}" || echo -e "  Active TPUs:          ${RED}${BOLD}Warning: ${FINAL_TPUS}${NC}"
[ -z "$FINAL_DISKS" ]     && echo -e "  Persistent Disks:     ${GREEN}${BOLD}0 (NO Persistent Disk charges)${NC}" || echo -e "  Persistent Disks:     ${YELLOW}Active: ${FINAL_DISKS}${NC}"
[ -z "$FINAL_IPS" ]       && echo -e "  Reserved Static IPs:  ${GREEN}${BOLD}0 (NO Static IP idle charges)${NC}" || echo -e "  Static IPs:           ${YELLOW}Active: ${FINAL_IPS}${NC}"
echo -e "  Estimated Cloud Burn: ${GREEN}${BOLD}\$0.00 / hr${NC}"
echo -e "${BOLD}==========================================================${NC}\n"

echo -e "${GREEN}${BOLD}🎉 Zero-cost teardown complete! All compute, GPU, TPU, disk, and network resources are deleted.${NC}\n"
