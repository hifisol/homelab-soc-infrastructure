# Homelab SOC Infrastructure

Production Homelab SOC (Security Operations Center) — threat detection, endpoint visibility, vulnerability management, network monitoring, and automated infrastructure deployment. Runs across bare-metal servers, TrueNAS SCALE, and Proxmox VE.

## Architecture

```
                     ┌─────────────────────────────────┐
                     │           UDM Pro SE            │
                     │    Firewall / IDS/IPS / Router  │
                     │    Syslog → Wazuh (5514/UDP)    │
                     └────────────────┬────────────────┘
                                      │
              ┌──────────────────────┬┴┬─────────────────────┐
              │                      │ │                     │
    ┌─────────▼────────┐   ┌─────────▼─▼───────┐   ┌─────────▼─────────┐
    │  Threat Hunter   │   │   Wazuh Manager   │   │   Docker Host     │
    │                  │   │                   │   │                   │
    │ • Zeek (NSM)     │   │ • Wazuh Manager   │   │ • Shuffle SOAR    │
    │ • RITA (Beacons) │   │ • Wazuh Indexer   │   │ • Netbox (DCIM)   │
    │ • AC-Hunter      │   │ • Wazuh Dashboard │   │ • Zabbix          │
    │ • GVM/OpenVAS    │   │ • Discord Alerts  │   │ • Portainer       │
    │ • Velociraptor   │   │ • MISP + VT       │   │ • Samba           │
    │                  │   │ • Syslog-ng       │   │                   │
    └──────────────────┘   └───────────────────┘   └───────────────────┘
              │                       │                     │
              │             ┌─────────▼────────┐            │
              │             │   Wazuh Agents   │            │
              │             │  (All Endpoints) │            │
              │             └──────────────────┘            │
              │                                             │
    ┌─────────▼────────┐                           ┌────────▼─────────┐
    │  Proxmox VE      │  ◄──── 20Gbps Bond ────►  │  TrueNAS SCALE   │
    │                  │       (2x 10G DAC)        │                  │
    │ • AD Lab VMs     │                           │ • ISO Library    │
    │ • CyberChef LXC  │                           │ • Velociraptor   │
    │ • MISP LXC       │                           │ • Wazuh Agent    │
    │ • VM Templates   │                           │ • Tailscale      │
    └──────────────────┘                           └──────────────────┘
```

## Repository Structure

```
homelab-soc-infrastructure/
├── ansible/                             # Infrastructure automation
│   ├── playbooks/
│   │   ├── ad-lab/                      # AD lab deploy/teardown on Proxmox
│   │   ├── hardening/                   # CIS benchmarks, server baseline
│   │   ├── maintenance/                 # Service accounts, health checks
│   │   └── security-agents/             # Wazuh, Velociraptor, Zabbix, Tailscale
│   ├── templates/                       # Jinja2 templates (compose files)
│   ├── vars/                            # Variable files (examples only)
│   └── inventory/                       # Inventory examples
├── detection/                           # Wazuh detection engineering
│   ├── rules/                           # Custom Wazuh rules
│   │   ├── local_rules.xml              # Windows FP suppression, UniFi/UDM, WiFi attacks
│   │   ├── zeek_rules.xml               # Zeek network detection (50+ rules)
│   │   └── rita_rules.xml               # RITA beacon/C2 detection
│   ├── decoders/
│   │   └── zeek_decoders.xml            # Zeek TSV log parsing (8 log types)
│   ├── integrations/
│   │   ├── custom-discord-rita          # RITA alerts → Discord webhook
│   │   ├── custom-discord-wazuh         # Wazuh alerts → Discord webhook
│   │   ├── custom-shuffle               # Wazuh alerts → Shuffle SOAR
│   │   └── custom-misp                  # Wazuh alerts → MISP IOC lookup
│   └── scripts/
│       ├── rita-wazuh-export.sh         # RITA → Wazuh JSON bridge (hourly)
│       └── rita-daily-report.sh         # Daily RITA summary → Discord
├── docker/                              # Docker compositions
│   ├── velociraptor-compose.yml         # Velociraptor DFIR server
│   ├── velociraptor-dockerfile          # Custom container build
│   ├── shuffle-compose.yml              # Shuffle SOAR (backend, frontend, orborus)
│   ├── misp-compose.yml                 # MISP threat intel (core, modules, DB, Redis)
│   ├── cyberchef-compose.yml            # CyberChef web UI + API server
│   ├── zabbix-compose.yml               # Zabbix + PostgreSQL
│   └── netbox-compose.yml               # Netbox DCIM + PostgreSQL + Redis
├── persistence/                         # TrueNAS post-init scripts
│   ├── ensure-velociraptor.sh           # Survives TrueNAS A/B boot updates
│   ├── ensure-wazuh.sh
│   └── ensure-tailscale.sh
├── scripts/
│   └── netbox-discovery.sh              # Infrastructure auto-discovery
└── docs/
    ├── gvm-quickstart.md                # GVM/OpenVAS setup guide
    └── truenas-persistence.md           # TrueNAS service persistence guide
```

---

## Detection Engineering

Custom Wazuh detection rules, Zeek network monitoring decoders, RITA beacon analysis integration, and Discord alerting.

### Detection Coverage

| Category | Rule IDs | Description |
|----------|----------|-------------|
| Windows FP Suppression | 100001-100017 | Tuned whitelist rules reducing false positives |
| UniFi/UDM Network | 100100-100137 | Firewall blocks, IDS/IPS, Tor, threat management, device offline |
| CVE Detection | 100138-100142 | Symlink TOCTOU (CVE-2026-20677) on Linux + macOS |
| DeepBlueCLI | 100150-100157 | Windows event log hunting — password spray, mimikatz, obfuscated PS, log clearing |
| Encrypted DNS C2 | 100160-100166 | DoT/DoH/DoQ detection via Sysmon (Windows) |
| RITA Beacons | 100200-100270 | C2 beacon scoring, blacklist contacts, long connections |
| Zeek Network | 100300-100499 | Suspicious ports, DNS threats, HTTP anomalies, SSL issues, SSH brute force |
| Zeek DNS C2 | 100500-100510 | Encrypted DNS detection (DoT/DoH/DoQ) via Zeek |
| DNS Security | 100550-100604 | Domain intel matches, DNS bypass detection |
| Iranian APT | 100800-100860 | Pioneer Kitten, Peach Sandstorm, MuddyWater TTPs |
| WiFi Attack Detection | 100130-100135 | Deauth floods, evil twin, PMKID, beacon anomalies |

### Alerting Pipeline

```
UDM Pro ──syslog──► Wazuh Manager ──► Discord (#wazuh-alerts)
                             ▲    │
Zeek ──logs──► Wazuh Agent ──┘    ├──► Shuffle SOAR (automated triage)
                         ▲        ├──► MISP (IOC correlation)
RITA ──JSON──► Wazuh ────┘────────├──► VirusTotal (FIM hash checks)
                         ▲        └──► Discord (#rita-alerts)
DeepBlueCLI ──log──► Wazuh Agent (Windows) ──► Wazuh Manager
  (Scheduled Task, every 15 min — Security + System log analysis)

CyberChef API ◄── Shuffle workflows (decode/defang/extract IOCs)
MISP ◄── VT enrichment (on-demand IOC lookup)
```

### Zeek Log Coverage

8 log types with custom TSV decoders:

| Log | Detections |
|-----|------------|
| `conn.log` | Suspicious ports (Metasploit 4444, IRC, Tor), large transfers |
| `dns.log` | NXDOMAIN floods, DGA domains, DNS tunneling |
| `http.log` | Suspicious user agents, executable downloads, web scanning |
| `ssl.log` | Self-signed certs, expired certs, weak TLS versions |
| `notice.log` | Port scans, address scans, protocol violations |
| `ssh.log` | Brute force detection, credential compromise |
| `files.log` | Executable transfers, script delivery, archive downloads |
| `weird.log` | Network protocol anomalies |

---

## Ansible Automation

18 playbooks for security agent deployment, server hardening, AD lab orchestration, and infrastructure maintenance.

### Playbooks

| Category | Playbook | Description |
|----------|----------|-------------|
| **AD Lab** | `deploy.yml` | Full lab deployment — Windows Server DC, Kali, CommandoVM, Ubuntu, Security Onion |
| | `teardown.yml` | Selective or full lab destruction (preserves templates) |
| | `templates.yml` | VM template creation from ISOs with BIOS/TPM/VirtIO config |
| **Hardening** | `cis-benchmark-phase1.yml` | SSH, accounts, filesystem, network hardening |
| | `cis-benchmark-phase2.yml` | Auditd, log forwarding, file integrity (AIDE), PAM |
| | `server-baseline.yml` | Base security config for all new servers |
| **Agents** | `install-security-agents.yml` | Combined Velociraptor + Wazuh deployment |
| | `install-velociraptor.yml` | DFIR endpoint agent |
| | `install-wazuh-agent.yml` | SIEM agent via Tailscale mesh |
| | `install-zabbix-agent.yml` | Monitoring agent |
| | `install-tailscale.yml` | VPN mesh deployment |
| | `install-gvm.yml` | GVM/OpenVAS vulnerability scanner |
| **Maintenance** | `add-service-account.yml` | SSH key-based service account provisioning |
| | `check-services.yml` | Service health validation |
| | `setup-user.yml` | Standard user provisioning |

### AD Lab Architecture

Automated deployment of an isolated red team / pentesting lab on Proxmox:

- Isolated network bridge (`vmbr2`) with no route to production
- Tag-based deployment: `--tags kali`, `--tags dc,commando`, etc.
- Cloud-init support for Linux VMs
- Templates preserved across teardown/redeploy cycles

---

## Docker Services

| Service | Composition | Purpose |
|---------|------------|---------|
| Shuffle SOAR | `shuffle-compose.yml` | Security orchestration and automated response |
| MISP | `misp-compose.yml` | Threat intelligence platform (VT enrichment enabled) |
| CyberChef | `cyberchef-compose.yml` | Data analysis — decode, defang, extract IOCs |
| Velociraptor | `velociraptor-compose.yml` | DFIR endpoint visibility |
| Zabbix | `zabbix-compose.yml` | Infrastructure monitoring |
| Netbox | `netbox-compose.yml` | DCIM / asset management |

---

## TrueNAS Persistence

TrueNAS SCALE overwrites the root filesystem on updates (A/B boot). Post-init scripts on ZFS datasets recreate systemd services on every boot:

| Script | Service | Survives Updates Via |
|--------|---------|---------------------|
| `ensure-velociraptor.sh` | Velociraptor | Binary on data pool |
| `ensure-wazuh.sh` | Wazuh Agent | `/var/ossec` (writable overlay) |
| `ensure-tailscale.sh` | Tailscale | Binary on data pool, state in `/var/lib` |

---

## Network Design

| Segment | Purpose |
|---------|---------|
| Management VLAN | Server SSH, web UIs |
| Infrastructure VLAN | Storage, NAS, hypervisors |
| AD Lab (vmbr2) | Isolated pentesting lab |
| Storage Bond | 20Gbps point-to-point (Proxmox ↔ TrueNAS) |

### Storage Bond
- 2x 10GbE DAC direct connections (no switch)
- Proxmox: `bond0` (balance-rr) → `vmbr1` for VM storage access
- TrueNAS: `bond0` (LOADBALANCE/balance-xor)
- Jumbo frames (MTU 9000) end-to-end

---

## Integrations

### Wazuh Integrations

| Integration | Trigger | Purpose |
|-------------|---------|---------|
| VirusTotal | `syscheck` (FIM) alerts | Auto-check file hashes against VT on every file change |
| MISP | Level 3+ alerts | IOC correlation — IPs, domains, hashes matched against threat intel |
| Shuffle SOAR | Level 10+ alerts | Automated triage workflows — enrich, deduplicate, escalate |
| Discord | Level 10+ / RITA rules | Real-time alert notifications to SOC channels |

### MISP Enrichment Modules

| Module | Purpose |
|--------|---------|
| `virustotal_public` | Hash/IP/domain lookup (rate-limited, free tier) |
| `virustotal` | Full VT enrichment for MISP attributes |

### Shuffle SOAR Workflows

| Workflow | Trigger | Actions |
|----------|---------|---------|
| Alert Triage | Wazuh level 10+ | Enrich via MISP/VT, deduplicate, notify Discord |
| CyberChef Decode | On-demand | Decode Base64/hex payloads, extract IOCs, defang URLs |

---

## Technologies

| Category | Tools |
|----------|-------|
| **SIEM** | Wazuh |
| **SOAR** | Shuffle |
| **Threat Intel** | MISP (VirusTotal enrichment) |
| **NSM** | Zeek |
| **DFIR** | Velociraptor |
| **Data Analysis** | CyberChef (web UI + API) |
| **Windows Event Log Hunting** | DeepBlueCLI (SANS) |
| **Beacon Detection** | RITA, AC-Hunter |
| **Vuln Scanning** | GVM/OpenVAS |
| **Monitoring** | Zabbix |
| **DCIM** | Netbox |
| **VPN** | Tailscale |
| **Hypervisor** | Proxmox VE |
| **Storage** | TrueNAS SCALE (ZFS) |
| **Networking** | Ubiquiti UniFi (UDM Pro SE) |
| **Containers** | Docker, LXC |
| **Automation** | Ansible |
| **Alerting** | Discord webhooks |
