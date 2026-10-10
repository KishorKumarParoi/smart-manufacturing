#!/usr/bin/env bash
# ==============================================================================
# ONE-CLICK AUTONOMOUS DEPLOYMENT RUNNER FOR SMART MANUFACTURING DEVOPS PLATFORM
# Provisions GCP VM 'gitops' (if needed) & bootstraps all 12 enterprise tools
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If running on macOS or outside VM without sudo, run with --provision-vm
if [[ "$OSTYPE" == "darwin"* ]] || [ "$EUID" -ne 0 ]; then
    bash "${SCRIPT_DIR}/scripts/install-ubuntu-tools.sh" --provision-vm "$@"
else
    sudo bash "${SCRIPT_DIR}/scripts/install-ubuntu-tools.sh" "$@"
fi
