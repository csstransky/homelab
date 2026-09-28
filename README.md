# MOTHERLODE Homelab

Personal homelab server running Debian 13 (Trixie).

MOTHERLODE provides:

* NAS / file storage
* ZFS
* Samba
* Nextcloud
* Tailscale
* Media storage
* Local AI
* Ollama
* Pi coding agent
* NVIDIA GPU compute

## Repository Philosophy

This repository is the operational memory of MOTHERLODE.

It should contain enough information for a future human or AI agent to understand:

* what the machine is
* how it is configured
* why important decisions were made
* how services are deployed
* how failures were diagnosed
* how the machine can be rebuilt

The goal is **reproducibility, not documentation for documentation's sake.**

---

## Repository Structure

```text
.
├── AGENTS.md                 # Instructions for AI agents
├── README.md                 # Project overview
│
├── ai/                       # AI architecture and model setup
│   ├── README.md
│   ├── pi/
│   ├── ollama/
│   └── models/
│
├── compose/                  # Docker Compose projects
├── nextcloud/                # Nextcloud configuration
├── samba/                    # Samba configuration/documentation
├── zfs/                      # ZFS documentation/configuration
├── systemd/                  # Custom systemd units
│
├── scripts/
│   ├── diagnostics/
│   ├── install/
│   ├── backup/
│   └── maintenance/
│
└── docs/
    ├── architecture/
    ├── hardware/
    ├── services/
    ├── recovery/
    └── checkpoints/
```

---

## Hardware

### MOTHERLODE

```text
HP Z240 Tower
Intel Core i7-6700
16 GiB RAM
NVIDIA GeForce GTX 1050 Ti 4 GB
Debian 13 Trixie
```

The machine has previously experienced intermittent hardware/boot/sleep instability. See the hardware and recovery documentation before diagnosing those problems.

---

## Storage

The primary storage layer is ZFS mounted at:

```text
/tank
```

Persistent disk references should use:

```text
/dev/disk/by-id/
```

rather than `/dev/sdX`.

---

## AI

MOTHERLODE runs local AI through Ollama.

Current models:

```text
qwen3:4b
qwen3:14b
```

Pi provides the coding-agent interface.

See:

```text
ai/README.md
```

and:

```text
AGENTS.md
```

---

## Recovery Documentation

Important incidents are documented under:

```text
docs/recovery/
```

In particular:

```text
docs/recovery/NVIDIA-DRIVER-INCIDENT.md
```

The NVIDIA document records a previous incompatibility between the GTX 1050 Ti and the NVIDIA open kernel module.

---

## Change Policy

Before changing MOTHERLODE:

```bash
git status
git diff
```

After changing MOTHERLODE:

* verify the change
* update documentation
* review the Git diff
* commit intentional changes

Do not commit credentials or secrets.

