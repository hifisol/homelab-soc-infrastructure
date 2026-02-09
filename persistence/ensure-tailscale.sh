#!/bin/bash
# TrueNAS SCALE Post-Init Script: Tailscale VPN
# Recreates the systemd service after TrueNAS updates (A/B boot wipes root FS)
#
# Prerequisites:
#   - Tailscale static binaries stored on a data pool
#   - Already authenticated (state persists in /var/lib/tailscale)
#   - Registered in TrueNAS: System > Advanced > Init/Shutdown Scripts (Post Init)
#
# Usage:
#   Place static binaries on a persistent dataset:
#     /mnt/<pool>/system/tailscale/tailscale
#     /mnt/<pool>/system/tailscale/tailscaled

POOL_PATH="/mnt/data-pool/system/tailscale"
TAILSCALE="${POOL_PATH}/tailscale"
TAILSCALED="${POOL_PATH}/tailscaled"
SERVICE_FILE="/etc/systemd/system/tailscaled.service"
DEFAULTS_FILE="/etc/default/tailscaled"
STATE_DIR="/var/lib/tailscale"
SOCKET="/var/run/tailscale/tailscaled.sock"

# Check prerequisites
if [ ! -f "$TAILSCALED" ]; then
    echo "[ERROR] tailscaled binary not found at $TAILSCALED"
    exit 1
fi

# Create state and socket directories
mkdir -p "$STATE_DIR"
mkdir -p "$(dirname $SOCKET)"

# Create defaults file
cat > "$DEFAULTS_FILE" << EOF
FLAGS="--state=${STATE_DIR}/tailscaled.state --socket=${SOCKET}"
EOF

# Create systemd service
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Tailscale Node Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${DEFAULTS_FILE}
ExecStart=${TAILSCALED} \$FLAGS
ExecStopPost=/bin/sh -c "rm -f ${SOCKET}"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable tailscaled.service
systemctl start tailscaled.service

echo "[OK] Tailscale daemon started successfully"
sleep 2

# Check status
if [ -f "$TAILSCALE" ]; then
    ${TAILSCALE} --socket="$SOCKET" status 2>/dev/null || echo "[INFO] Run 'tailscale up' if not yet authenticated"
fi
