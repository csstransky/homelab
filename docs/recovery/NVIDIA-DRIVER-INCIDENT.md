# NVIDIA Driver Incident — GTX 1050 Ti / Pascal

## Date

2026-09-28

## Severity

High

## Status

RESOLVED

---

## Summary

MOTHERLODE's NVIDIA GPU stopped working after installing NVIDIA/CUDA-related packages while setting up Ollama.

The system began failing to initialize the NVIDIA driver with:

```text
nvidia 0000:01:00.0: probe with driver nvidia failed with error -1
```

The machine was still bootable, but the NVIDIA driver could not initialize the GPU.

The root cause was an incompatible NVIDIA kernel module.

MOTHERLODE uses:

```text
NVIDIA GeForce GTX 1050 Ti
Pascal architecture
```

The installed NVIDIA 615.71.09 package selected the NVIDIA open kernel module.

The NVIDIA open kernel module does not support this Pascal GPU.

---

## Critical Lesson

### DO NOT USE NVIDIA OPEN KERNEL MODULES ON THE GTX 1050 Ti

The correct Debian configuration is the proprietary NVIDIA kernel module:

```text
nvidia-kernel-dkms
```

Do not install:

```text
nvidia-kernel-open-dkms
```

Do not select an `nvidia-open` configuration for this GPU.

---

## Symptoms

The kernel reported:

```text
nvidia 0000:01:00.0: probe with driver nvidia failed with error -1
```

Additional kernel messages included:

```text
NVRM: installed in this system is not supported by open
NVRM: nvidia.ko because it does not include the required GPU
NVRM: System Processor (GSP).
```

The module was loading but could not initialize the GPU.

---

## Important Diagnostic Evidence

Secure Boot was disabled:

```text
secureboot: Secure boot disabled
```

Therefore Secure Boot was not the cause.

The NVIDIA kernel module was also clearly being loaded:

```text
nvidia: loading out-of-tree module taints kernel.
```

The decisive evidence was:

```text
NVRM: installed in this system is not supported by open
NVRM: nvidia.ko because it does not include the required GPU
NVRM: System Processor (GSP).
```

This identifies the problem as GPU/module compatibility.

---

## Incorrect Configuration

The failed installation used NVIDIA 615.71.09 and the open kernel module.

The machine's GPU is Pascal-generation hardware and does not provide the GSP capability required by the NVIDIA open kernel module.

Therefore the open module was fundamentally incompatible with this GPU.

---

## Recovery

### 1. Disable the NVIDIA CUDA repository

The CUDA repository had been added at:

```text
/etc/apt/sources.list.d/cuda-debian13-x86_64.list
```

It was disabled rather than left available to continually influence NVIDIA package selection.

The disabled file was:

```text
/etc/apt/sources.list.d/cuda-debian13-x86_64.list.disabled
```

Do not re-enable the CUDA repository merely to install the NVIDIA driver.

---

### 2. Remove the incompatible 615.71.09 packages

The bad NVIDIA package set was identified by version:

```text
615.71.09-2
```

Those packages were purged.

---

### 3. Install Debian's proprietary NVIDIA driver

The correct Debian Trixie packages were:

```text
nvidia-driver
nvidia-kernel-dkms
```

Installation:

```bash
sudo apt install linux-headers-$(uname -r) nvidia-kernel-dkms nvidia-driver
```

This installed:

```text
nvidia-driver       550.163.01-2
nvidia-kernel-dkms  550.163.01-2
```

---

### 4. Verify DKMS

The `dkms` executable is located at:

```text
/usr/sbin/dkms
```

Because `/usr/sbin` may not be in a normal user's PATH, use:

```bash
sudo /usr/sbin/dkms status 'nvidia*'
```

Expected result:

```text
nvidia-current/550.163.01, 6.12.107+deb13-amd64, x86_64: installed
```

---

### 5. Verify the GPU

Run:

```bash
nvidia-smi
```

Successful recovery produced:

```text
NVIDIA-SMI 550.163.01
Driver Version: 550.163.01
CUDA Version: 12.4
NVIDIA GeForce GTX 1050 Ti
4096 MiB
```

The GPU subsequently operated normally.

---

## Final Working Configuration

```text
GPU:
    NVIDIA GeForce GTX 1050 Ti
    Pascal
    4 GB VRAM

Driver:
    Debian NVIDIA proprietary driver
    550.163.01

Kernel module:
    nvidia-current
    DKMS

Required package:
    nvidia-kernel-dkms

Do NOT use:
    nvidia-kernel-open-dkms
    NVIDIA open kernel module
```

---

## Ollama Result

After the driver was corrected, Ollama successfully used the GPU.

Current local models include:

```text
qwen3:4b
qwen3:14b
```

Qwen3 4B was observed to offload approximately 80% of its workload to the GPU during testing.

Qwen3 14B was substantially more GPU/CPU constrained and was much slower.

---

## Prevention Rules

Before installing NVIDIA software on MOTHERLODE:

### Check the GPU

```bash
lspci -nn | grep -Ei 'vga|3d|nvidia'
```

### Check the current NVIDIA packages

```bash
dpkg-query -W -f='${binary:Package} ${Version}\n' \
  | grep -Ei 'nvidia|cuda'
```

### Check DKMS

```bash
sudo /usr/sbin/dkms status
```

### Verify the kernel driver

```bash
nvidia-smi
```

Do not install a different NVIDIA kernel-module flavor simply because it is newer.

GPU architecture compatibility takes priority over package version.

---

## Recovery Checklist

If NVIDIA breaks again:

1. Do not repeatedly reboot.
2. Capture:

```bash
nvidia-smi
uname -r
lspci -nn | grep -Ei 'vga|3d|nvidia'
sudo /usr/sbin/dkms status
journalctl -k --no-pager | grep -Ei 'nvidia|nvrm|gsp'
```

3. Check whether the open kernel module was installed.
4. Confirm Secure Boot status.
5. Confirm the GPU architecture.
6. Prefer Debian's proprietary `nvidia-kernel-dkms` for this Pascal GPU.
7. Verify with `nvidia-smi`.

---

## Root Cause

**The incident was caused by installing the NVIDIA open kernel module on a Pascal GTX 1050 Ti.**

It was not caused by:

* Secure Boot
* ZFS
* Docker
* Ollama itself
* Nextcloud
* Samba
* Tailscale

The open NVIDIA kernel module was simply incompatible with the GPU.

---

## Status

RESOLVED.

The machine is now using the proprietary NVIDIA DKMS driver and the GTX 1050 Ti is functioning normally.

