# GVM (Greenbone Vulnerability Management) Quick Start Guide

## Quick Access

| Item | Value |
|------|-------|
| **Web URL** | `http://<threat-hunter-ip>:9392` |
| **Username** | admin |
| **Password** | (set during installation) |
| **Installation Path** | /opt/greenbone/ |
| **Docker Compose** | /opt/greenbone/docker-compose.yml |

## Quick Start

### Step 1: Open Your Browser
**Use HTTP, not HTTPS:**
```
http://<threat-hunter-ip>:9392
```

### Step 2: Login
- Username: `admin`
- Password: (configured via `install-gvm.yml` playbook or manually)

### Step 3: Wait for Feed Synchronization
- First login may take 1-2 minutes to load
- Feeds (vulnerability data) sync in background (can take hours on first run)
- You can start configuring targets immediately

## Common Troubleshooting

### "Connection Refused" or Site Not Reachable

```bash
# Check if containers are running
ssh deploy-svc@<threat-hunter-ip>
cd /opt/greenbone
sudo docker compose ps

# If containers are down, start them
sudo docker compose up -d

# Check logs for errors
sudo docker compose logs --tail 50
```

### Feed Sync Status

```bash
# Check if feeds are syncing
sudo docker compose logs gvmd --tail 20 | grep -i "sync\|feed\|update"

# NVT feed count (should be 100k+)
sudo docker compose exec gvmd gvmd --get-feeds
```

### Reset Admin Password

```bash
sudo docker compose exec gvmd gvmd --user=admin --new-password=<new-password>
```

## Running a Scan

1. **Configuration > Targets** - Add target IPs/subnets
2. **Scans > Tasks** - Create new task with target and scan config
3. **Start** the task (play button)
4. Monitor progress in the Tasks view

### Recommended Scan Configs
| Config | Use Case | Duration |
|--------|----------|----------|
| Full and fast | Standard vulnerability assessment | 30-60 min per /24 |
| Full and deep | Thorough scan with slower checks | 2-4 hours per /24 |
| Discovery | Host/service discovery only | 5-10 min per /24 |

## Architecture

```
Docker Compose Stack:
├── gvmd          - Greenbone Vulnerability Manager daemon
├── ospd-openvas  - OpenVAS scanner wrapper
├── pg-gvm        - PostgreSQL database
├── redis-server  - Redis for scanner data
├── gsa           - Greenbone Security Assistant (web UI, port 9392)
├── mqtt-broker   - MQTT for scanner communication
└── notus-scanner - Package-based vulnerability detection
```
