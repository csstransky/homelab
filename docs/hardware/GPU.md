# GPU — GTX 1050 Ti status and return plan

## Status (2026-10-09): back in and working

The user put the card back in. It has been in every boot since 2026-10-07 21:03 and works:

| Check (2026-10-09) | Result |
|---|---|
| `lspci` / `nvidia-smi` | GP107 at `01:00.0`, driver 550.163.01, 34 °C idle |
| PCIe link | x16 (max x16) |
| Display | Xorg and the desktop run on the card. The HD 530 iGPU is off while it is installed. |
| `Xid` / "fallen off the bus" in the kernel log | 0, in all 5 boots since 2026-10-07 |
| Ollama | Sees it: `inference compute ... library=Vulkan ... NVIDIA GeForce GTX 1050 Ti ... total="4.2 GiB"` |
| Hard freezes | None since it went back in. The kernel panics in `docs/recovery/2026-10-04-ZFS-PANIC.md` happened both with the card (09-28, 10-04, 10-09) and without it (10-06), so it is not their cause. |

Steps 1–3 of the test procedure below (VRAM, gpu-burn, PSU under combined load) have not been
run. Run them before calling the card load-tested. The sections below are the history and
the plan written while the card was out.

### Earlier status (2026-10-04, card out)

| Item | State |
|---|---|
| GTX 1050 Ti 4 GB (GP107, `10de:1c82`) | Removed from the machine. Hardware untested. |
| Display | Intel HD Graphics 530 (CPU iGPU, `8086:1912`), in-kernel `i915`, monitor on the motherboard output |
| NVIDIA packages | Still installed (driver 550.163.01, proprietary `nvidia-kernel-dkms`). Do not remove them. |
| Ollama | Running CPU-only. It sees the HD 530 via Vulkan and correctly skips it (`dropping integrated GPU`). |

Expected harmless boot errors while the card is out: `NVRM: No NVIDIA GPU found`,
`Failed to insert module 'nvidia_drm'`, `nvidia-persistenced.service` failed.

## Why it was removed

1. Both hard freezes (2026-09-28 and 2026-09-29, see
   `docs/recovery/2026-09-28-HARD-FREEZE.md`) happened while the desktop/display path was
   active on the NVIDIA card. RAM, memory controller and CPU passed 47 h of memtest86+ and a
   23 h Linux burn-in, so the NVIDIA driver/Xorg display path is the leading suspect. It is
   not proven.
2. On the HP Z240, the iGPU only appears on the PCI bus with the card out. With the card
   installed the BIOS left the HD 530 off, so the display could not be moved off the
   NVIDIA card. Removing the card was the only way to get integrated graphics working.

## What has not been tested

- The GTX 1050 Ti itself: VRAM, compute under sustained load, thermals.
- The PSU under combined CPU + GPU load (memtest86+ and the burn-in touched neither).
- Whether the freezes stop when the NVIDIA card is not driving a display.

Until the steps below pass, treat the card as **unverified**, not as known-good.

## Plan: return as a compute-only card on the strict NAS

Once MOTHERLODE is a strict NAS (managed over SSH/Tailscale, no daily desktop use), put
the card back for **Ollama/CUDA only**. Nothing drives a display on it:

- Boot target `multi-user.target` (`sudo systemctl set-default multi-user.target`), so
  no Xorg runs on the NVIDIA card.
- Monitor on the motherboard output if F10 setup has an option to keep integrated video on
  with a card installed (option name on the Z240 not yet confirmed). Otherwise, no
  monitor, or a monitor on the card for BIOS/console only.
- Stay on proprietary `nvidia-kernel-dkms`. **Never** the open module (see
  `docs/recovery/NVIDIA-DRIVER-INCIDENT.md`).

Removing the display path is also the test. If the freezes stop, the display path was the
cause, and the card is fine for compute.

## Test procedure (run when the card goes back in)

All steps run from `multi-user.target`, never from the desktop.

**0. Install and sanity check.** Reseat the card and clean the dust. Then:

```bash
lspci -nn | grep -i nvidia
nvidia-smi
nvidia-smi -q | grep -A2 'Link Width'        # expect x16
sudo systemctl isolate multi-user.target
```

**Monitors, running for every step below:**

```bash
# driver errors: any "Xid" or "fallen off the bus" = fail
sudo dmesg -wT | grep -iE 'NVRM|Xid'
# temps, power, clocks, throttle reasons every 5 s
nvidia-smi --query-gpu=timestamp,temperature.gpu,power.draw,clocks.sm,clocks.mem,utilization.gpu,memory.used,clocks_throttle_reasons.active \
  --format=csv -l 5 | tee ~/burnin-logs/gpu-$(date +%F).csv
```

**1. VRAM, about 1 h: memtest_vulkan.** It runs on the installed `nvidia-vulkan-icd`.
Download the Linux x86_64 release from
<https://github.com/GpuZelenograd/memtest_vulkan/releases>, run it for an hour, then stop it
with Ctrl+C. Pass: 0 errors.

**2. Verified compute, about 2 h: gpu-burn.** It checks every result, so a faulty card
shows errors instead of only running hot. It needs `nvcc` (Debian `nvidia-cuda-toolkit`
12.4, which matches driver 550; several GB):

```bash
sudo apt install nvidia-cuda-toolkit
git clone https://github.com/wilicc/gpu-burn ~/gpu-burn && cd ~/gpu-burn
make CUDAPATH=/usr COMPUTE=61        # Pascal sm_61
./gpu_burn 7200
```

Pass: the card is reported `OK` with 0 errors.

**3. PSU under full system load, 2–4 h.** Run both at once:

```bash
./gpu_burn 14400
stress-ng --cpu 8 --vm 2 --vm-bytes 4G --verify -t 4h
```

Pass: no freeze or reboot, and no errors from either tool.

**4. Real use, 1–2 weeks.** Run headless with Ollama on the GPU (`ollama ps` shows
`100% GPU` for qwen3:4b). Keep the panic capture from the freeze doc in place.

### Pass criteria

- 0 memtest_vulkan errors, 0 gpu-burn errors, no `Xid` in `dmesg`.
- GPU temperature stays below ~85 °C. Under full load the only throttle reason should be
  the power cap. A thermal throttle means cleaning or better airflow.
- No freezes in step 3 or step 4.

### Reading a failure

| Result | Meaning |
|---|---|
| VRAM errors, gpu-burn errors or `Xid` lines | Card is bad. Replace it or leave it out. |
| Freezes only under step 3 combined load | Suspect the PSU. |
| Clean headless; freezes return only when a desktop runs on the NVIDIA card | Display driver path, not hardware. Keep the card compute-only. |

Record the results and date here when the test is done.
