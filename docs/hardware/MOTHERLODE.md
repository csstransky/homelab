# MOTHERLODE — Hardware Inventory

**Recorded:** 2026-09-28. All six drives report SMART overall health PASSED on this date; detailed attributes are refreshed in Checkpoint 3.

## System

| Item | Value |
|---|---|
| Model | HP Z240 Tower Workstation, serial 2UA8301V83 |
| Board | HP 802F, serial PESRHAACYAQ5Q6 (replacement board installed during the 2026-09 rebuild) |
| BIOS | N51 Ver. 01.70, 2018-06-19 |
| CPU | Intel Core i7-6700 @ 3.40 GHz, 4 cores / 8 threads, VT-x, 8 MiB L3 |
| RAM | 16 GiB: 4 × 4 GB DDR4-2133, non-ECC, DIMM1–DIMM4 |
| GPU | NVIDIA GeForce GTX 1050 Ti 4 GB (GP107, `10de:1c82`), proprietary driver 550.163.01. **Removed 2026-10-04, untested**; returns compute-only on the strict NAS. See `GPU.md`. |
| Display | Intel HD Graphics 530 iGPU (`8086:1912`, `i915`). Only visible on the PCI bus with the NVIDIA card out. |
| Secure Boot | disabled (required for ZFS module) |
| PSU | replaced during the 2026-09 rebuild |

## Network

| Interface | MAC | Address (2026-09-28) |
|---|---|---|
| `eno1` — Intel I219-LM (`8086:15b7`) | `18:60:24:ad:92:ac` | 192.168.1.59/24, **UniFi fixed-IP reservation** (set 2026-09-28), gateway 192.168.1.1 |

Use the MAC above for the Ubiquiti DHCP reservation (Checkpoint 1).

## Storage controllers

| Controller | Notes |
|---|---|
| Intel 100 Series SATA (`8086:2822`) | **Reports as "RAID mode" in the BIOS.** Linux drives it with `ahci`. Leave as-is unless it causes problems; changing SATA mode can affect boot. |
| ASMedia ASM1064 4-port SATA card (`1b21:1064`) | PCIe 8 GT/s x1. Adds the ports needed for five HDDs. |
| ASUS DRW-24B1ST optical drive | `/dev/sr0`, ignore |
| Generic USB card reader | `/dev/sdg`–`/dev/sdj`, 0 B, ignore |

## Drives

Stable identifiers. `/dev/sdX` letters change between boots and must never be used in configuration.

| by-id (`/dev/disk/by-id/`) | Model | Size | Role |
|---|---|---|---|
| `ata-Crucial_CT250MX200SSD1_154511053F30` | Crucial MX200 SSD | 250 GB | Debian OS (`/`, `/boot/efi`, 12 GiB swap). **Never touch.** |
| `ata-WDC_WD10EZEX-60M2NA0_WD-WCC3F2CYKRSN` | WD Caviar Blue | 1 TB | `tank1tb` mirror member |
| `ata-TOSHIBA_DT01ACA100_Z5B2VRDNS` | Toshiba DT01ACA100 | 1 TB | `tank1tb` mirror member (24 pending sectors on 09-14; watch it) |
| `ata-WDC_WD6400AAKS-00A7B2_WD-WCASYD471432` | WD Caviar Blue | 640 GB | part1: `tank500gb` mirror member; part2: ext4 `other` (~128 G) |
| `ata-ST500DM002-1BD142_W2AF3DHD` | Seagate Barracuda | 500 GB | `tank500gb` mirror member |
| `ata-ST2000DX002-2DV164_Z4ZB3346` | Seagate FireCuda | 2 TB | `media` single-disk pool. Questionable SMART history: disposable data only. |

SMART baseline per drive: see the 2026-09-14 HDD health report summary in
`docs/checkpoints/CHECKPOINTS.md` (section 0) and the fresh readings to be added in Checkpoint 3.

## Known hardware quirks

- Intermittent long POST, boot delays, sleep/wake instability (see `AGENTS.md`).
- BIOS message `Error sending end of POST message to ME: HECI disabled, proceeding with boot!` seen during the rebuild.
- Do not attribute these to software without evidence.
