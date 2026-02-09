#!/bin/bash
# TrueNAS SCALE Post-Init Script: Velociraptor Agent
# Recreates the systemd service after TrueNAS updates (A/B boot wipes root FS)
#
# Prerequisites:
#   - Velociraptor binary stored on a data pool (survives updates)
#   - Client config stored alongside the binary
#   - Registered in TrueNAS: System > Advanced > Init/Shutdown Scripts (Post Init)
#
# Usage:
#   Place binary + config on a persistent dataset:
#     /mnt/<pool>/system/velociraptor/velociraptor
#     /mnt/<pool>/system/velociraptor/client.config.yaml

POOL_PATH="/mnt/data-pool/system/velociraptor"
BINARY="${POOL_PATH}/velociraptor"
CONFIG="${POOL_PATH}/client.config.yaml"
SERVICE_FILE="/etc/systemd/system/velociraptor.service"
WRITEBACK="/etc/velociraptor.writeback.yaml"

# Check prerequisites
if [ ! -f "$BINARY" ]; then
    echo "[ERROR] Velociraptor binary not found at $BINARY"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "[ERROR] Client config not found at $CONFIG"
    exit 1
fi

# Create systemd service
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Velociraptor Client Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BINARY} client -v --config ${CONFIG} --writeback ${WRITEBACK}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable velociraptor.service
systemctl start velociraptor.service

echo "[OK] Velociraptor agent started successfully"
systemctl status velociraptor.service --no-pager
