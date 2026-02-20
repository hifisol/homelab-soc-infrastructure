#!/bin/bash

# Netbox Infrastructure Discovery Script
# Gathers device information from infrastructure hosts via SSH
# and outputs JSON suitable for Netbox API import

OUTPUT_FILE="${1:-./netbox-inventory.json}"
TEMP_DIR="/tmp/netbox-discovery-$$"
mkdir -p "$TEMP_DIR"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Netbox Infrastructure Discovery Script ==="
echo "Output will be saved to: $OUTPUT_FILE"
echo ""

# Initialize JSON array
echo "[" > "$OUTPUT_FILE"
FIRST_ENTRY=true

# Function to gather info from a host
gather_host_info() {
    local hostname=$1
    local ip=$2
    local ssh_user=${3:-"deploy-svc"}
    local ssh_key=${4:-"~/.ssh/id_ed25519"}

    echo -e "${YELLOW}[*] Gathering info from $hostname ($ip)...${NC}"

    # Test connectivity first
    if ! ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
        echo -e "${RED}[!] $hostname is unreachable${NC}"
        return 1
    fi

    # Gather information via SSH
    local info=$(ssh -i "$ssh_key" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$ssh_user@$ip" '
        # OS Information
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_NAME="$NAME"
            OS_VERSION="$VERSION"
        else
            OS_NAME="Unknown"
            OS_VERSION="Unknown"
        fi

        # Hostname
        HOSTNAME=$(hostname)

        # Kernel
        KERNEL=$(uname -r)

        # Hardware info (if available)
        if command -v dmidecode >/dev/null 2>&1; then
            MANUFACTURER=$(sudo dmidecode -s system-manufacturer 2>/dev/null | head -1 | tr -d "\n")
            MODEL=$(sudo dmidecode -s system-product-name 2>/dev/null | head -1 | tr -d "\n")
            SERIAL=$(sudo dmidecode -s system-serial-number 2>/dev/null | head -1 | tr -d "\n")
        else
            MANUFACTURER="Unknown"
            MODEL="Unknown"
            SERIAL="Unknown"
        fi

        # Network interfaces
        PRIMARY_IP=$(ip -4 addr show | grep -oP "(?<=inet\s)\d+(\.\d+){3}" | grep -v "127.0.0.1" | head -1)
        PRIMARY_IFACE=$(ip -4 route show default | grep -oP "(?<=dev\s)\S+" | head -1)
        MAC_ADDR=$(ip link show "$PRIMARY_IFACE" 2>/dev/null | grep -oP "(?<=link/ether\s)\S+" | head -1)

        # Docker containers
        DOCKER_CONTAINERS=""
        if command -v docker >/dev/null 2>&1; then
            DOCKER_CONTAINERS=$(sudo docker ps --format "{{.Names}}" 2>/dev/null | tr "\n" "," | sed "s/,$//" || echo "")
        fi

        # Running services (common ones)
        SERVICES=""
        for svc in wazuh-manager gvmd zabbix-server portainer netbox nginx apache2; do
            if sudo systemctl is-active --quiet "$svc" 2>/dev/null || \
               sudo systemctl status "$svc" 2>/dev/null | grep -q "active (running)"; then
                SERVICES="$SERVICES,$svc"
            fi
        done
        SERVICES=$(echo "$SERVICES" | sed "s/^,//")

        # Listening ports
        LISTENING_PORTS=$(sudo ss -tlnp 2>/dev/null | grep LISTEN | awk "{print \$4}" | grep -oP ":\K\d+$" | sort -n | uniq | tr "\n" "," | sed "s/,$//" || echo "")

        # Output as pipe-delimited
        echo "$HOSTNAME|$OS_NAME|$OS_VERSION|$KERNEL|$MANUFACTURER|$MODEL|$SERIAL|$PRIMARY_IP|$PRIMARY_IFACE|$MAC_ADDR|$DOCKER_CONTAINERS|$SERVICES|$LISTENING_PORTS"
    ' 2>/dev/null)

    if [ -z "$info" ]; then
        echo -e "${RED}[!] Failed to gather info from $hostname${NC}"
        return 1
    fi

    # Parse the pipe-delimited output
    IFS='|' read -r h_hostname h_os_name h_os_version h_kernel h_manufacturer h_model h_serial \
                    h_primary_ip h_primary_iface h_mac h_docker h_services h_ports <<< "$info"

    echo -e "${GREEN}[+] Successfully gathered info from $hostname${NC}"

    # Add comma if not first entry
    if [ "$FIRST_ENTRY" = false ]; then
        echo "," >> "$OUTPUT_FILE"
    fi
    FIRST_ENTRY=false

    # Write JSON object
    cat >> "$OUTPUT_FILE" << EOF
  {
    "name": "$hostname",
    "primary_ip": "$ip",
    "actual_hostname": "$h_hostname",
    "manufacturer": "$h_manufacturer",
    "model": "$h_model",
    "serial_number": "$h_serial",
    "platform": "$h_os_name",
    "os_version": "$h_os_version",
    "kernel": "$h_kernel",
    "primary_interface": "$h_primary_iface",
    "mac_address": "$h_mac",
    "docker_containers": "$h_docker",
    "services": "$h_services",
    "listening_ports": "$h_ports",
    "status": "active",
    "site": "Primary"
  }
EOF
}

# ============================================================
# Add your hosts here
# ============================================================
# gather_host_info "hostname" "192.168.1.10" "deploy-svc" "~/.ssh/id_ed25519"
# gather_host_info "hostname" "192.168.1.20" "deploy-svc" "~/.ssh/id_ed25519"

echo ""
echo "NOTE: Edit this script to add your infrastructure hosts."
echo "Example:"
echo '  gather_host_info "wazuh-mgr" "192.168.1.10" "deploy-svc" "~/.ssh/id_ed25519"'

# Close JSON array
echo "" >> "$OUTPUT_FILE"
echo "]" >> "$OUTPUT_FILE"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}=== Discovery Complete ===${NC}"
echo "Results saved to: $OUTPUT_FILE"
echo ""
echo "To view results:  cat $OUTPUT_FILE | jq ."
echo "To import to Netbox, use the API with this JSON data."
