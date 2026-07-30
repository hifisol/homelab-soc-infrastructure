# Defender for Endpoint P2 (Dev)

Personal dev/testing environment for Microsoft Defender for Endpoint Plan 2 — onboarding, ASR rule tuning, and Graph API advanced-hunting export into this lab's Wazuh manager. This is where onboarding playbooks and ASR baselines get validated against lab endpoints before they're productized for client rollouts in the separate `hifisol/defender-endpoint-p2` repo (HiFi Solutions client tooling, kept in its own repo/lifecycle rather than mixed in here).

## Why this exists separately from `hifisol/defender-endpoint-p2`

Same reasoning as `ansible/` vs `sentri-automation`/`Appliances` elsewhere in this project: this repo is the personal lab where things get built and broken safely (own tenant, own endpoints, throwaway configs). The client repo only gets tooling once it's been proven here.

## Structure

```
defender-endpoint-p2/
├── ansible/
│   ├── inventory/
│   │   └── hosts.yml.example         # Copy to hosts.yml, fill in lab endpoint IPs
│   ├── playbooks/
│   │   ├── onboard-linux.yml         # mdatp install + onboarding
│   │   └── health-check.yml         # Onboarding/sensor health verification
│   └── vars/
│       └── mde-defaults.yml.example  # Copy to mde-defaults.yml, fill in tenant onboarding path
└── docs/
    └── lab-notes.md                   # Findings from ASR audit tuning, Graph API pull testing, etc.
```

## Status

Scaffold stage — onboarding playbooks are written but not yet validated end-to-end against a lab endpoint with a real MDE P2 tenant. Next steps are tracked in [`docs/lab-notes.md`](docs/lab-notes.md).

## Quick Start

```bash
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
cp ansible/vars/mde-defaults.yml.example ansible/vars/mde-defaults.yml
# fill in lab endpoint IPs and onboarding blob path, then:
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/health-check.yml
```
