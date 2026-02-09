#!/bin/bash
# TrueNAS SCALE Post-Init Script: Wazuh Agent
# Recreates the user/group and systemd service after TrueNAS updates
#
# Prerequisites:
#   - Wazuh agent installed to /var/ossec (writable, survives updates)
#   - ossec.conf configured with manager IP
#   - Registered in TrueNAS: System > Advanced > Init/Shutdown Scripts (Post Init)
#
# Note: /var is writable on TrueNAS SCALE and persists across updates,
#       so Wazuh binaries and config at /var/ossec remain intact.
#       Only the user/group and systemd service need recreation.

WAZUH_DIR="/var/ossec"
SERVICE_FILE="/etc/systemd/system/wazuh-agent.service"

# Check prerequisites
if [ ! -d "$WAZUH_DIR" ]; then
    echo "[ERROR] Wazuh directory not found at $WAZUH_DIR"
    exit 1
fi

# Recreate wazuh user and group (may not exist after update)
if ! getent group wazuh >/dev/null 2>&1; then
    groupadd -r wazuh
    echo "[OK] Created wazuh group"
fi

if ! getent passwd wazuh >/dev/null 2>&1; then
    useradd -r -g wazuh -d "$WAZUH_DIR" -s /sbin/nologin wazuh
    echo "[OK] Created wazuh user"
fi

# Fix ownership
chown -R wazuh:wazuh "$WAZUH_DIR"

# Create systemd service
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Wazuh Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=${WAZUH_DIR}/bin/wazuh-control start
ExecStop=${WAZUH_DIR}/bin/wazuh-control stop
ExecReload=${WAZUH_DIR}/bin/wazuh-control restart
PIDFile=${WAZUH_DIR}/var/run/wazuh-agentd.pid
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable wazuh-agent.service
systemctl start wazuh-agent.service

echo "[OK] Wazuh agent started successfully"
${WAZUH_DIR}/bin/wazuh-control status
