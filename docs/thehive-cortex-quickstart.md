# TheHive + Cortex Quick Start Guide

## Purpose

Case management and alert enrichment for the homelab SOC stack. Wazuh/Graylog
alerts get a formal triage -> investigate -> close workflow, with Cortex
auto-enriching observables (IPs, hashes, domains, URLs) against VirusTotal,
AbuseIPDB, and other analyzers.

Same pattern already used for the other Docker-based stacks in this repo
(Zabbix, Netbox, Velociraptor): Docker Compose, config templated by Ansible,
admin UI bound to `127.0.0.1` only, reached via Twingate/Tailscale.

## Placement

Deployed via `ansible/playbooks/security-agents/install-thehive-cortex.yml`
against the `docker_hosts` inventory group. Currently planned to run on a
dev VM on PM-1 until [[pm-2-buildout|PM-2]] (a second Proxmox host, HP Z700)
is stood up, at which point it's expected to move there permanently.

## Quick Access

| Item | Value |
|------|-------|
| **TheHive UI** | `https://<docker-host-ip>:9001` |
| **Cortex UI** | `https://<docker-host-ip>:9002` |
| **Install path** | `/opt/thehive/` |
| **Docker Compose** | `/opt/thehive/docker-compose.yml` |

## Setup

1. Copy `ansible/vars/thehive-cortex.yml.example` to `ansible/vars/thehive-cortex.yml` and fill in real secrets (`pwgen -N 1 -s 64` for `thehive_secret`/`cortex_secret`, analyzer API keys for VirusTotal/AbuseIPDB)
2. Add the target host to the `docker_hosts` group in your inventory
3. Run the playbook:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/security-agents/install-thehive-cortex.yml --tags thehive_cortex
   ```

## Post-Deployment Checklist

- [ ] Log into TheHive UI via Twingate/Tailscale, create initial organization + analyst users
- [ ] Log into Cortex UI, enable VirusTotal and AbuseIPDB analyzers, attach API keys
- [ ] Link Cortex to TheHive (Organization -> Cortex Servers)
- [ ] Wire up alert forwarding from Wazuh/Graylog -> TheHive webhook (not yet automated - the alert schema needs to map cleanly from the source alert JSON to TheHive's `/api/v1/alert` fields: source, sourceRef, title, tags)
- [ ] Fire a test alert, confirm it lands as a TheHive alert with enrichment

## Sizing Note

TheHive runs on Cassandra + Elasticsearch-adjacent storage, Cortex runs its
own worker pool - all three are JVM-based and can be CPU-hungry, especially
during Cassandra compaction. Recommend at minimum 4 cores / 8GB RAM dedicated
to this stack if it's sharing a box with anything else. This is why it's
running as its own dev VM on PM-1 rather than alongside the existing
Shuffle/Zabbix/Netbox stack on RDNT-1 (a 2-core box already running one
JVM-based stack - not enough headroom for a second).

## Open Items

- [ ] Alert forwarding mapping (Wazuh/Graylog -> TheHive webhook) not yet built
- [ ] Not yet validated against a live deployment - vars file is currently all `CHANGE_ME` placeholders
- [ ] Decide whether this stays a personal/homelab-only tool or eventually gets productized like [[hifi-client-deploy-repo|the client-facing SENTRI/RTMS-1 stack]] (not currently planned - this was explicitly scoped as homelab-only)
