# Network Port Map

Tracks which physical device/NIC is plugged into which switch port, per switch.
Goal is to eventually cover every managed switch in the homelab, so any NIC's
switch port (and what VLANs that port carries) can be looked up without having
to open the UniFi controller or re-run discovery every time.

## Layout

```
network-map/
├── unifi-inventory.yml     # UniFi network devices (switches, APs, etc.) on 10.18.56.0/24
├── protect-inventory.yml   # UniFi Protect devices (cameras, chime, doorbell, NVR) on 10.18.121.0/24
└── switches/
    └── <switch-name>.yml   # one file per physical switch, port-level mapping
```

The `*-inventory.yml` files are device lists (name, model, IP, MAC, status) —
pulled from the UniFi controller/Protect device list. `switches/<name>.yml`
goes one level deeper: which specific port on that switch has what plugged
into it.

## Entry format

```yaml
switch: <name>
model: <model, or CHANGE_ME if unknown>
location: <physical location>
ports:
  <port-number>:
    device: <hostname of what's plugged in>
    interface: <NIC name on that device>
    mac: "<MAC address>"
    mode: trunk | access
    vlans: [<vlan ids the port carries>]   # for access ports, a single-element list
    notes: <how this was confirmed, and when>
```

## How to confirm a port mapping

No LLDP available on most hosts in this homelab yet, so mappings are confirmed one of two ways:

1. **UniFi controller** — look up the device's MAC under Clients / the switch's Port Manager topology view. Fastest when you have controller access handy.
2. **Passive tcpdump on the host** — `sudo tcpdump -i <nic> -nn -e vlan or arp or broadcast` for ~15s. 802.1Q-tagged broadcast/multicast traffic (IGMP reports, mDNS, UDM discovery packets) reveals every VLAN the port is trunked for, without touching any config. Used to confirm PM-1 `nic1` → basement switch port 12 (see `switches/basement-switch.yml`).

Add entries as ports get confirmed — this is expected to fill in gradually, not all at once.
