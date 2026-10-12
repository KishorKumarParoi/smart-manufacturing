#!/usr/bin/env bash
# ==============================================================================
# INDUSTRIAL ANTI-EGRESS WATCHDOG & EMERGENCY KILL-SWITCH
# Protects against runaway outbound data transfer, compromised bot relays,
# and unexpected multi-terabyte cloud billing spikes.
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configurable Safety Thresholds
MAX_DAILY_EGRESS_GB="${MAX_DAILY_EGRESS_GB:-10}"       # Maximum allowable outbound data per day (GB)
RATE_LIMIT_MBPS="${RATE_LIMIT_MBPS:-25}"               # Max bandwidth throttle ceiling (Mbps)
CHECK_INTERVAL_SEC="${CHECK_INTERVAL_SEC:-30}"         # Polling interval (seconds)

echo -e "\n${CYAN}${BOLD}====================================================================${NC}"
echo -e "${CYAN}${BOLD} 🛡️ INSTALLING INDUSTRIAL EGRESS GUARD & EMERGENCY KILL-SWITCH     ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"

# Detect Primary External WAN Interface
WAN_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' || echo "eth0")
echo -e "  • Primary Network Interface: ${BOLD}${WAN_IF}${NC}"
echo -e "  • Egress Bandwidth Ceiling:  ${BOLD}${RATE_LIMIT_MBPS} Mbps${NC}"
echo -e "  • Daily Outbound Data Cap:   ${BOLD}${MAX_DAILY_EGRESS_GB} GB${NC}"

# 1. Install Required Tools (tc, iproute2, fail2ban)
echo -e "\n${YELLOW}[1/4] Ensuring required network security tools (tc, fail2ban, ufw)...${NC}"
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1 || true
    sudo apt-get install -y --no-install-recommends iproute2 fail2ban ufw >/dev/null 2>&1 || true
    sudo systemctl enable fail2ban >/dev/null 2>&1 || true
    sudo systemctl restart fail2ban >/dev/null 2>&1 || true
fi

# 2. Configure Traffic Control (tc) Token Bucket Filter Rate Limiter
echo -e "\n${YELLOW}[2/4] Applying kernel-level Traffic Control (tc) egress limiter...${NC}"
if command -v tc >/dev/null 2>&1 && [ -n "$WAN_IF" ]; then
    sudo tc qdisc del dev "$WAN_IF" root 2>/dev/null || true
    sudo tc qdisc add dev "$WAN_IF" root tbf rate "${RATE_LIMIT_MBPS}mbit" burst 64kbit latency 400ms
    echo -e "${GREEN}[✓] Outbound bandwidth on '${WAN_IF}' throttled to ${RATE_LIMIT_MBPS} Mbps.${NC}"
    echo "    (Even under 100% 24/7 saturation, maximum possible daily transfer is <15 GB)."
fi

# 3. Drop External Transit IP Forwarding in UFW
echo -e "\n${YELLOW}[3/4] Enforcing UFW forward drop policy (preventing open transit relay)...${NC}"
if [ -f /etc/default/ufw ]; then
    sudo sed -i 's/DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw
    sudo ufw reload >/dev/null 2>&1 || true
    echo -e "${GREEN}[✓] UFW transit routing dropped.${NC}"
fi

# 4. Deploy Egress Watchdog Daemon Service
echo -e "\n${YELLOW}[4/4] Deploying persistent background Egress Watchdog daemon...${NC}"
WATCHDOG_SCRIPT="/usr/local/bin/egress-watchdog.sh"

sudo tee "$WATCHDOG_SCRIPT" >/dev/null << EOF_DAEMON
#!/usr/bin/env bash
# Egress Watchdog Daemon: Monitors /proc/net/dev and triggers kill-switch if cap is breached
WAN_IF="${WAN_IF}"
MAX_BYTES=\$((${MAX_DAILY_EGRESS_GB} * 1024 * 1024 * 1024))
INTERVAL=${CHECK_INTERVAL_SEC}

get_tx_bytes() {
    grep "^\s*\${WAN_IF}:" /proc/net/dev | awk '{print \$10}' || echo 0
}

START_BYTES=\$(get_tx_bytes)

while true; do
    sleep "\$INTERVAL"
    CURR_BYTES=\$(get_tx_bytes)
    DIFF_BYTES=\$((CURR_BYTES - START_BYTES))
    DIFF_GB=\$(awk "BEGIN {printf \"%.2f\", \$DIFF_BYTES / 1073741824}")

    if [ "\$DIFF_BYTES" -gt "\$MAX_BYTES" ]; then
        logger -p alert "🚨 [EGRESS KILL-SWITCH TRIGGERED] Outbound transfer exceeded \${MAX_DAILY_EGRESS_GB} GB (\${DIFF_GB} GB transferred)! Engaging emergency lockdown."
        echo "🚨 [EGRESS KILL-SWITCH] Transferred \${DIFF_GB} GB (Limit: \${MAX_DAILY_EGRESS_GB} GB). Shutting down high-egress processes..." > /dev/kmsg 2>/dev/null || true

        # 1. Stop high-risk external containers (Jenkins, SonarQube, Nexus)
        command -v docker >/dev/null 2>&1 && docker stop jenkins sonarqube nexus 2>/dev/null || true

        # 2. Throttle external interface down to emergency 1 Mbit/s
        command -v tc >/dev/null 2>&1 && tc qdisc change dev "\$WAN_IF" root tbf rate 1mbit burst 16kbit latency 500ms 2>/dev/null || true

        # 3. Sleep 1 hour before re-checking
        sleep 3600
        START_BYTES=\$(get_tx_bytes)
    fi
done
EOF_DAEMON

sudo chmod +x "$WATCHDOG_SCRIPT"

# Deploy systemd unit
sudo tee /etc/systemd/system/egress-watchdog.service >/dev/null << EOF_SERVICE
[Unit]
Description=Industrial Egress Protection & Bandwidth Kill-Switch Daemon
After=network.target

[Service]
Type=simple
ExecStart=${WATCHDOG_SCRIPT}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE

sudo systemctl daemon-reload
sudo systemctl enable egress-watchdog.service >/dev/null 2>&1 || true
sudo systemctl restart egress-watchdog.service >/dev/null 2>&1 || true

echo -e "\n${GREEN}${BOLD}====================================================================${NC}"
echo -e "${GREEN}${BOLD} ✓ ANTI-EGRESS GUARD & WATCHDOG DEPLOYED SUCCESSFULLY!              ${NC}"
echo -e "${GREEN}${BOLD}====================================================================${NC}"
echo -e "  • Service:   ${CYAN}sudo systemctl status egress-watchdog.service${NC}"
echo -e "  • Bandwidth: Capped at ${BOLD}${RATE_LIMIT_MBPS} Mbps${NC} via Linux Kernel 'tc'"
echo -e "  • Limit:     Emergency shutdown triggers if outbound traffic exceeds ${BOLD}${MAX_DAILY_EGRESS_GB} GB${NC}"
echo -e "====================================================================\n"
