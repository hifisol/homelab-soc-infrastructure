# TrueNAS SCALE - Service Persistence Across Updates

## The Problem

TrueNAS SCALE uses an A/B boot scheme: when you update, it writes the new OS to the inactive boot partition and switches to it. This **overwrites the root filesystem**, which means:

- `/etc/systemd/system/*.service` files are deleted
- System users/groups created manually are removed
- `/etc/default/*` config files are wiped
- Any packages installed via `dpkg`/`apt` are gone (TrueNAS blocks these anyway)

## What Survives

| Path | Survives Update | Notes |
|------|:---:|-------|
| `/mnt/<pool>/` | Yes | ZFS datasets, your data |
| `/var/` | Yes | Writable overlay, persists |
| `/etc/` | Partial | Some files persist, systemd services do not |
| `/usr/` | No | Read-only, replaced on update |
| `/opt/` | No | Read-only, replaced on update |

## The Solution: Post Init Scripts

Store binaries and configs on a ZFS dataset (e.g., `/mnt/data-pool/system/`), then use **Post Init scripts** to recreate systemd services on every boot.

### Setup

1. Create a persistent directory on your data pool:
```bash
mkdir -p /mnt/data-pool/system/{velociraptor,wazuh,tailscale}
```

2. Place binaries and configs there:
```bash
# Example: Velociraptor
cp velociraptor /mnt/data-pool/system/velociraptor/
cp client.config.yaml /mnt/data-pool/system/velociraptor/

# Example: Tailscale (static binaries)
cp tailscale tailscaled /mnt/data-pool/system/tailscale/
```

3. Place the `ensure-*.sh` scripts alongside:
```bash
cp ensure-velociraptor.sh /mnt/data-pool/system/velociraptor/
cp ensure-wazuh.sh /mnt/data-pool/system/wazuh/
cp ensure-tailscale.sh /mnt/data-pool/system/tailscale/
chmod +x /mnt/data-pool/system/*/ensure-*.sh
```

4. Register in TrueNAS Web UI:
   - **System > Advanced > Init/Shutdown Scripts**
   - Add each script as **Type: Post Init**
   - Command: `/mnt/data-pool/system/velociraptor/ensure-velociraptor.sh`

### What Each Script Does

| Script | Actions |
|--------|---------|
| `ensure-velociraptor.sh` | Creates systemd service pointing to pool binary + config, starts agent |
| `ensure-wazuh.sh` | Recreates `wazuh` user/group, fixes ownership on `/var/ossec`, creates systemd service, starts agent |
| `ensure-tailscale.sh` | Creates defaults file, systemd service pointing to pool binaries, starts daemon |

### Special Case: Wazuh

Wazuh is unique because its binaries live in `/var/ossec`, which **does** survive updates (since `/var` is writable). Only the user/group and systemd service need recreation.

The Wazuh agent was installed via manual `deb` extraction (since TrueNAS blocks `dpkg`):
```bash
# One-time installation (extract deb without dpkg)
ar x wazuh-agent_*.deb
tar xf data.tar.gz -C /
```

After that, the `ensure-wazuh.sh` script handles everything on subsequent boots/updates.

### Special Case: Tailscale

Tailscale state is stored in `/var/lib/tailscale/tailscaled.state`, which survives updates. This means you only need to authenticate (`tailscale up`) once. After that, the ensure script just recreates the service and the daemon picks up the existing state.

**Note:** If DNS isn't configured after an update, Tailscale may fail to reach the coordination server:
```bash
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
```

## Verification

After a reboot or update, verify all services:
```bash
systemctl status velociraptor
systemctl status wazuh-agent
systemctl status tailscaled
```

If a service didn't start, run the ensure script manually:
```bash
/mnt/data-pool/system/velociraptor/ensure-velociraptor.sh
```

## Layout Example

```
/mnt/data-pool/system/
├── velociraptor/
│   ├── velociraptor              # Binary
│   ├── client.config.yaml        # Client configuration
│   └── ensure-velociraptor.sh    # Post Init script
├── wazuh/
│   └── ensure-wazuh.sh           # Post Init script (binaries in /var/ossec)
└── tailscale/
    ├── tailscale                 # CLI binary (static)
    ├── tailscaled                # Daemon binary (static)
    └── ensure-tailscale.sh       # Post Init script
```
