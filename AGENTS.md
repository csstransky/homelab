# AGENTS.md — MOTHERLODE AI Agent Instructions

## Purpose

This repository documents and manages the MOTHERLODE homelab.

MOTHERLODE is a Debian 13 (Trixie) home server used for:

* NAS / file storage
* ZFS storage
* Samba
* Nextcloud
* Tailscale
* Media storage
* Local AI / Ollama
* AI coding agents
* NVIDIA GPU compute

This repository is intended to be both:

1. Human documentation for rebuilding and maintaining MOTHERLODE.
2. Machine-readable context for AI coding agents working on the system.

**Read this file before making changes.**

---

## Host

| Property        | Value                           |
| --------------- | ------------------------------- |
| Hostname        | `MOTHERLODE`                    |
| OS              | Debian 13 (Trixie)              |
| Architecture    | x86_64                          |
| CPU             | Intel Core i7-6700              |
| RAM             | 16 GiB                          |
| GPU             | NVIDIA GeForce GTX 1050 Ti 4 GB |
| Primary user    | `ghost`                         |
| Boot/storage OS | SSD                             |
| Data storage    | ZFS `/tank`                     |

---

## Core Rules

### 1. Do not destroy data

Never run destructive commands against disks, ZFS pools, datasets, partitions, or filesystems without explicitly confirming the target first.

Do not blindly use:

```bash
zpool destroy
zpool create -f
wipefs -a
dd
mkfs
fdisk
parted
sgdisk
```

Before destructive storage operations:

1. Identify the exact device.
2. Verify `/dev/disk/by-id/` identity.
3. Check current mounts and ZFS state.
4. Explain what will be destroyed.
5. Obtain explicit confirmation.

---

### 2. Use stable disk identifiers

Never use `/dev/sda`, `/dev/sdb`, etc. for persistent ZFS configuration.

Prefer:

```text
/dev/disk/by-id/
```

---

### 3. Protect existing services

Do not casually modify or reinstall:

* ZFS
* Docker
* Nextcloud AIO
* Samba
* Tailscale
* Home Assistant
* existing systemd services

Understand the current configuration before changing it.

---

### 4. Home Assistant is independent

Home Assistant runs separately from MOTHERLODE.

Do not move Home Assistant onto MOTHERLODE merely for convenience.

---

### 5. Secrets never belong in Git

Never commit:

* API keys
* OAuth tokens
* passwords
* private keys
* `~/.pi/agent/auth.json`
* `.env` files containing secrets
* Tailscale authentication secrets
* cloud credentials

Use sanitized examples instead.

---

## AI Architecture

MOTHERLODE has both local and cloud AI.

### Local

Ollama provides local models through:

```text
http://localhost:11434
```

Current models:

```text
qwen3:4b
qwen3:14b
```

Pi accesses Ollama through its OpenAI-compatible API:

```text
http://localhost:11434/v1
```

Pi configuration:

```text
~/.pi/agent/models.json
```

The current provider configuration is documented in:

```text
ai/pi/README.md
```

---

## NVIDIA GPU

GPU:

```text
NVIDIA GeForce GTX 1050 Ti
4 GB VRAM
Pascal architecture
```

The GTX 1050 Ti requires the proprietary NVIDIA kernel module.

**Do NOT install the NVIDIA open kernel module on this machine.**

In particular, do not replace:

```text
nvidia-kernel-dkms
```

with:

```text
nvidia-kernel-open-dkms
```

See:

```text
docs/recovery/NVIDIA-DRIVER-INCIDENT.md
```

before changing NVIDIA packages.

---

## AI Model Selection

Current intended roles:

### Qwen3 4B

Primary local/fast model.

Use for:

* quick questions
* local/private work
* lightweight coding
* testing
* situations where cloud access is unnecessary

### Qwen3 14B

Larger local model.

Use when:

* additional local reasoning capability is useful
* slower inference is acceptable

It is substantially slower on the GTX 1050 Ti than Qwen3 4B.

### Cloud models

Cloud providers may be used for more demanding coding or reasoning tasks.

Do not assume that every model displayed by a provider's catalog is actually authorized for the current account.

Always test the selected model before documenting it as supported.

---

## Change Management

Before making significant changes:

```bash
git status
git diff
```

After making changes:

1. Test the change.
2. Update documentation.
3. Review the diff.
4. Commit only intentional changes.

Prefer small, understandable commits.

---

## Documentation Principle

If a problem required substantial troubleshooting, document:

1. Symptoms
2. Diagnosis
3. Evidence
4. Root cause
5. Fix
6. Verification
7. How to prevent recurrence

Do not document only the final command.

The troubleshooting history is valuable system knowledge.

---

## AI Agent Behavior

An AI agent should:

* inspect before changing
* make small changes
* explain risky commands
* preserve working services
* avoid unnecessary reinstalls
* verify assumptions with commands
* update documentation after significant changes
* never invent hardware specifications
* never assume a package is compatible merely because it exists in an APT repository

When uncertain, stop and gather evidence.

---

## Current Known Hardware Issue

MOTHERLODE has previously exhibited intermittent:

* unusually long POST times
* boot delays
* sleep/wake instability
* Firefox crashes after resume
* network instability after resume

These issues are separate from the NVIDIA driver incident unless evidence establishes otherwise.

Do not attribute hardware problems to software without evidence.

---

## Important Recovery Documentation

Before troubleshooting a known subsystem, read its recovery document if one exists.

Especially:

```text
docs/recovery/NVIDIA-DRIVER-INCIDENT.md
docs/recovery/BOOT-RECOVERY.md
```

These documents exist specifically to prevent repeating previous mistakes.

