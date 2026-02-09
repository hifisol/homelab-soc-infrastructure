# Homelab SOC Infrastructure

Production homelab SOC (Security Operations Center) infrastructure built for threat detection, endpoint visibility, vulnerability management, and network monitoring. Runs across bare-metal servers, TrueNAS SCALE, and Proxmox VE.

## Architecture

```
                           ┌─────────────────────────────────┐
                           │         UDM Pro SE              │
                           │    Firewall / IDS/IPS / Router  │
                           │    Syslog → Wazuh (5514/UDP)    │
                           └──────────┬──────────────────────┘
                                      │
              ┌───────────────────────┬┴┬───────────────────────┐
              │                       │ │                       │
    ┌─────────▼────────┐   ┌─────────▼─▼───────┐   ┌──────────▼────────┐
    │  Threat Hunter   │   │   Wazuh Manager   │   │   Docker Host     │
    │                  │   │                    │   │                   │
    │ • Zeek (NSM)     │   │ • Wazuh Manager    │   │ • Netbox (DCIM)   │
    │ • RITA (Beacons) │   │ • Wazuh Indexer    │   │ • Zabbix          │
    │ • AC-Hunter      │   │ • Wazuh Dashboard  │   │ • Portainer       │
    │ • GVM/OpenVAS    │   │ • Discord Alerts   │   │ • Samba           │
    │ • Velociraptor   │   │ • Syslog-ng        │   │                   │
    └──────────────────┘   └────────────────────┘   └───────────────────┘
              │                       │                       │
              │              ┌────────▼────────┐              │
              │              │  Wazuh Agents   │              │
              │              │  (All Endpoints) │              │
              │              └─────────────────┘              │
              │                                               │
    ┌─────────▼────────┐                          ┌───────────▼──────┐
    │  Proxmox VE      │◄── 20Gbps Bond ────────►│  TrueNAS SCALE   │
    │                   │   (2x 10G DAC)          │                  │
    │ • AD Lab VMs      │                          │ • ISO Library    │
    │ • VM Templates    │                          │ • Velociraptor   │
    │ • ISO Storage     │                          │ • Wazuh Agent    │
    │                   │                          │ • Tailscale      │
    └───────────────────┘                          └──────────────────┘
```

## Security Stack

| Component | Purpose | Integration |
|-----------|---------|-------------|
| **Wazuh** | SIEM, log analysis, FIM, threat detection | Agents on all endpoints, UDM syslog, Discord alerts |
| **Zeek** | Network security monitoring (NSM) | Mirrored port capture, logs forwarded to Wazuh agent |
| **RITA** | Beacon detection, C2 analysis | Hourly export to Wazuh JSON log, Discord alerts |
| **AC-Hunter** | Threat hunting dashboard | GUI frontend for RITA analysis |
| **Velociraptor** | DFIR, endpoint visibility | Server + agents on Linux/TrueNAS |
| **GVM/OpenVAS** | Vulnerability scanning | Docker deployment, port 9392 |
| **Zabbix** | Infrastructure monitoring | Agent-based, Docker stack |
| **Tailscale** | Zero-trust VPN mesh | Secure management plane across all hosts |

## Repository Structure

```
homelab-soc-infrastructure/
├── docker-compositions/           # Docker Compose files for services
│   ├── velociraptor-compose.yml   # Velociraptor DFIR server
│   ├── velociraptor-dockerfile    # Custom Velociraptor container
│   ├── zabbix-compose.yml         # Zabbix + PostgreSQL monitoring
│   └── netbox-compose.yml         # Netbox DCIM + PostgreSQL + Redis
├── scripts/
│   └── netbox-discovery.sh        # Infrastructure auto-discovery for Netbox
├── persistence/
│   ├── ensure-velociraptor.sh     # TrueNAS post-init: Velociraptor agent
│   ├── ensure-wazuh.sh            # TrueNAS post-init: Wazuh agent
│   └── ensure-tailscale.sh        # TrueNAS post-init: Tailscale VPN
└── docs/
    ├── gvm-quickstart.md          # GVM/OpenVAS setup and troubleshooting
    └── truenas-persistence.md     # Surviving TrueNAS updates (A/B boot)
```

## Docker Compositions

### Velociraptor DFIR Server
- Custom Dockerfile (Debian slim + Velociraptor binary)
- Ports: 8000 (agents), 8001 (API), 8889 (GUI)
- Persistent volumes for config, data, and logs

### Zabbix Monitoring Stack
- Zabbix Server + Web (Nginx) + PostgreSQL 15
- Port 8081 (web dashboard), 10051 (agent communication)
- Persistent database volume

### Netbox DCIM
- Netbox + PostgreSQL 15 + Redis 7
- Port 8080 (web interface)
- Persistent media and database volumes

## TrueNAS Persistence Scripts

TrueNAS SCALE uses an A/B boot scheme that overwrites the root filesystem on updates. Critical services are preserved via Post Init scripts stored on the data pool:

| Script | Service | What It Does |
|--------|---------|--------------|
| `ensure-velociraptor.sh` | Velociraptor | Recreates systemd service, starts agent |
| `ensure-wazuh.sh` | Wazuh Agent | Recreates user/group, systemd service, starts agent |
| `ensure-tailscale.sh` | Tailscale VPN | Recreates systemd service + defaults, starts daemon |

These are registered in TrueNAS **System > Advanced > Init/Shutdown Scripts** as Post Init tasks.

## Network Design

| Segment | Purpose |
|---------|---------|
| Management VLAN | Server SSH, web UIs |
| Infrastructure VLAN | Storage, NAS, hypervisors |
| AD Lab (vmbr2) | Isolated pentesting lab, no route to production |
| Storage Bond | 20Gbps point-to-point (Proxmox ↔ TrueNAS) |

### 20Gbps Storage Bond
- 2x 10GbE DAC direct connections (no switch)
- Proxmox: `bond0` (balance-rr) bridged to `vmbr1` for VM storage access
- TrueNAS: `bond0` (LOADBALANCE/balance-xor)
- Jumbo frames (MTU 9000) end-to-end

## Alerting Pipeline

```
UDM Pro ──syslog──► Wazuh Manager ──► Discord (#wazuh-alerts)
                         ▲
Zeek ──logs──► Wazuh Agent ──┘
                         ▲
RITA ──JSON──► Wazuh ────┘──────────► Discord (#rita-alerts)
```

## Technologies

- **Hypervisor:** Proxmox VE
- **Storage:** TrueNAS SCALE (ZFS)
- **SIEM:** Wazuh
- **NSM:** Zeek
- **DFIR:** Velociraptor
- **Vuln Scanning:** GVM/OpenVAS
- **Monitoring:** Zabbix
- **DCIM:** Netbox
- **VPN:** Tailscale
- **Networking:** Ubiquiti UniFi (UDM Pro SE)
- **Containers:** Docker, LXC
- **Automation:** Ansible
