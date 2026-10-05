# 2026-09-28 — Hard freeze during Checkpoint 1 commit

## Symptoms

- At roughly 23:19 EDT on 2026-09-28 MOTHERLODE froze completely while a Claude Code
  session was committing the Checkpoint 1 documentation. Nothing responded; the only way
  out was holding the power button for 5+ seconds. Reboot at 23:25.
- After reboot, `git status` in this repo failed:
  `error: object file .git/objects/06/6f8d0e... is empty` / `fatal: bad object HEAD`.
- `docs/architecture/network.md` (created seconds before the commit) was 0 bytes.

## Diagnosis

Journal of the crashed boot (`journalctl -b -1`):

- Last entry 23:18:42, a `smartctl -H` run from the session. Then nothing. No kernel
  oops, no panic, no OOM kill, no NVIDIA Xid, no MCE, no hung-task or lockup warning.
- Journal did not shut down cleanly (no `Journal stopped`); `last -x` records the session
  as `crash`.
- `/sys/fs/pstore` was empty after reboot, so the kernel never got to dump anything.
  **Wrong — corrected 2026-10-04:** `systemd-pstore` moves dumps out of `/sys/fs/pstore` at
  boot into `/var/lib/systemd/pstore/<epoch>/`. An Oops from this freeze was there all along
  (see "2026-10-04 follow-up" below).
- Ollama was idle (no requests since boot). RAM was not under pressure.
- Current boot: `EXT4-fs (sda2): orphan cleanup on readonly fs` — the root SSD lost
  in-flight writes, consistent with an abrupt power-off.

Git damage: nine loose objects in `.git/objects` were zero-length (the new commit, its
trees, and the blobs for the edited files), and `.git/refs/heads/master` already pointed
at the empty commit object. The reflog and the Claude session transcript both end in a
run of null bytes. This is the classic ext4 pattern after a crash: metadata (file size)
had been journaled but the data blocks never hit disk.

## Update after further investigation (same night)

- The crash happened while `apt install zfs-dkms zfsutils-linux` was compiling the ZFS
  kernel module: `/var/lib/dpkg/updates/` was timestamped 23:19 and `zfs-dkms` was left
  half-configured (`dpkg --configure -a` finished it at 23:45, and that second build ran
  clean with CPU package temp peaking at 55 °C). The journal's last entry (23:18:42) is
  earlier than the freeze; the last ~30 s of journal, `dpkg.log` and the Claude
  transcript were all lost to unflushed ext4 writes (null bytes in each).
- So the freeze hit under the heaviest sustained all-core load the machine had seen
  since the reinstall. That points at load-sensitive hardware: RAM, CPU memory
  controller, board VRM, or PSU.
- No machine-check (MCE), no PCIe AER, no thermal throttle counters, no GPU Xid in any
  boot since the 2026-09-27 reinstall. The HP board exposes no voltage sensors to Linux,
  so PSU rails cannot be read in software.
- Drive health (not the freeze cause, but found on the way): the OS SSD
  (`Crucial_CT250MX200SSD1`) reports 221 unexpected power losses in 565 cycles and only
  25 % rated life remaining; the Seagate 2 TB logged unreadable-sector (UNC) errors
  about 40 power-on hours ago; the Toshiba 1 TB still has 24 pending sectors.
- Journal history only covers 7 boots since the reinstall; this is the first recorded
  crash in that window. The earlier POST/sleep problems predate the reinstall and
  the board swap and are not in any log.
- `kernel.hardlockup_panic=1` and `kernel.softlockup_panic=1` are now set via
  `/etc/sysctl.d/90-lockup-panic.conf`; EFI pstore is active. Delete the file and run
  `sudo sysctl --system` to revert.
- Installed `memtest86+` (GRUB entry "Memory test"), `memtester`, `stress-ng`.

## Root cause

**Unknown hardware freeze, nothing logged.** Software causes that normally leave a trace
(kernel panic, OOM, GPU fault, disk I/O error) are ruled out by the absence of any log
line. A freeze this silent is usually hardware: RAM, power delivery, or board/firmware.
This machine already has a history of long POST times, sleep/wake instability and
network drops after resume (see `AGENTS.md`), and it runs non-ECC RAM. The board and
PSU were replaced during the 2026-09 rebuild.

The `git commit` itself was not the cause; it was just what was running.

## Fix

```bash
cd ~/homelab
cp -a .git /tmp/git-backup                                   # safety copy first
echo d36c733b757d6e6516d06c505f00e42b0e3b32f3 > .git/refs/heads/master   # last good commit (from .git/logs/HEAD)
find .git/objects -type f -empty -delete                     # drop the zero-byte objects
rm .git/index && git reset                                   # rebuild index; working tree untouched
git hash-object -t tree -w /dev/null                         # restore the empty-tree object fsck wanted
git fsck --full                                              # clean
```

The edits to `CHECKPOINTS.md` and `MOTHERLODE.md` survived in the working tree and were
re-committed. `network.md` was rewritten from the facts already in those two files.

## Verification

- `git fsck --full` exits 0 with no output.
- `git log` shows the re-created Checkpoint 1 commit on top of `d36c733`.

## Preventing a repeat, or at least catching the next one

1. **Run memtest86+ overnight** (it is in the Debian repo as `memtest86+`; add it to GRUB and
   boot into it). Non-ECC RAM that has been through a board swap is the first suspect for
   silent freezes.
2. **Make the kernel panic and dump on a lockup** so the next freeze leaves evidence in
   `/sys/fs/pstore` (EFI pstore is available on this box):
   ```bash
   sudo tee /etc/sysctl.d/90-lockup-panic.conf <<'EOT'
   kernel.hardlockup_panic = 1
   kernel.softlockup_panic = 1
   kernel.hung_task_panic = 0
   EOT
   sudo sysctl --system
   ```
   With this, a CPU lockup produces a stack trace in pstore instead of silence.
3. **Commit to Git early and often**; the repo is the record of the build and a crash
   during a commit is recoverable, but uncommitted new files are not.
4. The Toshiba 1 TB (`ata-TOSHIBA_DT01ACA100_Z5B2VRDNS`, future `tank1tb` mirror member)
   still reports **24 pending sectors** and smartd now warns about it on every start.
   Unrelated to the freeze (it is not the OS disk) but do not put it in the mirror
   without a full SMART long test first (Checkpoint 3).
5. smartd's mail hook fails because `/usr/bin/mail` is absent; install `bsd-mailx` or
   point `smartd.conf` at a different notifier during Checkpoint 3.

## Freeze signature (from the user)

Fans and LEDs stay on, screen frozen, keyboard dead (Caps Lock does not toggle), power
button ignored until held 5+ s. That is a CPU/RAM/board lockup, not a PSU drop
(a PSU fault turns the machine off or restarts it).

## Overnight burn-in (started 2026-09-28 23:55)

`scripts/diagnostics/burnin.sh` runs as `burnin.service` (`systemd-run`) and cycles:
memtester 9 GB → stress-ng vm verify 30 m → cpu verify 20 m → matrix 10 m →
cache/stream 10 m → compile-like mix 20 m → all-heavy 30 m, forever.
Log: `/home/ghost/burnin-logs/burnin-<date>.log`, fsync'd per line, 30 s samples of
CPU/GPU temps, load and free RAM. Per-phase output in the `.phases/` directory.

Stop: `sudo systemctl stop burnin`. Status: `systemctl status burnin`.

Reading the result the next morning:

- Machine frozen: the last `START` line without a matching `END` is the phase that
  killed it; the last `SAMPLE` gives the time and temps. Photograph the screen before
  power-cycling (a lockup now panics, so there may be a stack trace). After reboot check
  `sudo ls -R /var/lib/systemd/pstore/` (systemd moves dumps there; `/sys/fs/pstore` is emptied at boot).
- Machine alive, all phases `rc=0`, no `PROBLEM`: hours of full load did not trigger
  it. Next: memtest86+ overnight (below). If that is also clean, the remaining suspects
  are the board and firmware, and the freeze is not load-driven.
- Any phase `PROBLEM`/nonzero `rc` with the machine still up: memory or CPU is
  corrupting data silently. That is worse than a freeze; treat as failed RAM/IMC.

## memtest86+ (the definitive RAM/memory-controller test)

Reboot, and in the GRUB menu (shown for 5 s) pick **Memory test (memtest86+x64.efi)**.
Leave it for at least 4 full passes (all night). Errors are shown in red with the
physical address; a frozen memtest86+ screen is itself a result (CPU/board).

## Finding the exact bad stick

memtest86+ reports a physical address, but with four single-rank DIMMs in dual channel
the Skylake memory controller interleaves channels every few hundred bytes, so an
address does not map cleanly to one slot. Elimination is the reliable way:

1. Power off, unplug. One stick alone in **DIMM1**, run memtest86+ 2+ passes.
2. Repeat for each of the four sticks in the same slot. A stick that errors while the
   others pass in that slot is bad.
3. If every stick errors in DIMM1, put a known-good stick in DIMM2/3/4 in turn. If it
   errors everywhere, the CPU's memory controller or the board is at fault; if only one
   slot errors, the board is.
4. If everything passes alone but the full set fails together, try pairs in DIMM1+DIMM3
   (channel A) and DIMM2+DIMM4 (channel B).

DIMM slot numbering is printed on the Z240 board next to the slots.

## Kernel-side check with physical addresses (optional, morning after)

Debian's kernel has `CONFIG_MEMTEST`. Booting once with `memtest=8` on the kernel
command line (press `e` in GRUB, append to the `linux` line) runs 8 patterns over all
RAM before boot and logs bad ranges as `Bad RAM detected` with physical addresses in
`dmesg`; the kernel then avoids those pages. It is slower to boot but gives a
second opinion on memtest86+.

## 2026-10-04 follow-up: second freeze, memtest86+ result, conclusion

### The Sep 28 freeze did leave a dump

`/var/lib/systemd/pstore/1790651993/001/` (2026-09-28 23:19:53) holds a kernel Oops:

```
BUG: unable to handle page fault for address: fffffb394849d708
CPU: 4 ... Comm: Isolated Web Co  Tainted: P OE   (Firefox content process)
RIP: __list_del_entry_valid_or_report
  folios_put_refs <- free_pages_and_swap_cache <- unmap_vmas <- exit_mmap <- do_exit
```

A corrupted `struct page` list pointer, hit while a Firefox process was exiting. That is
kernel memory corruption: bad RAM, or a kernel module writing where it should not (the
proprietary `nvidia` module is the only out-of-tree code loaded). `panic_on_oops` was 0,
so the kernel limped on holding page-allocator state and the machine wedged. The other
dump in that directory (`1790557610`, 2026-09-27) is the old nouveau crash from the
NVIDIA driver incident and is unrelated.

### Second freeze: 2026-09-29 ~22:37 during burn-in

Symptoms (user): black screen, mouse pointer still moves, nothing else responds.

Evidence:

- Burn-in had run 22 h 40 m: 8 full cycles, 56/56 phases `rc=0`, `failed: 0` in every
  stress-ng verify run. Peak CPU package 87 °C, minimum free RAM 3.2 GB. (Every `END` line
  said `PROBLEM:` — a false positive: the filter matched stress-ng's `failed: 0`. Fixed in
  `burnin.sh` 2026-10-04.)
- Timeline (journal, `/var/log/Xorg.0.log.old`, `/var/log/Xorg.1.log`, burn-in log):

  | Time | Event |
  |---|---|
  | 22:36:25 | Monitor wakes from DPMS (greeter X log: DFP-1 disconnected, then reconnected) |
  | 22:36:35 | User unlocks; lightdm greeter X server (`:1`) exits cleanly |
  | ~22:36:43 | Desktop X (`:0`) re-probes outputs and re-adds input devices; its log ends mid-probe |
  | 22:36:46 | Last journal entry |
  | 22:36:51 | Last fsync'd burn-in sample: 47 °C, load 1, 4.7 GB free, `memtester` running |
  | 22:37:21 | Next sample never written; memtester `END` (due ~22:49) and smartd (22:55) never logged |

- No pstore dump, no Xid, no OOM kill, no hung-task line, no MCE. Nothing reached disk after
  22:36:51. The kernel still handled USB input (pointer moved), so it was not a hard CPU
  lockup — those would have panicked into pstore. It looks like a sleeping deadlock, which
  the lockup detectors do not catch.
- The OS SSD's `Unexpect_Power_Loss_Ct` went 221 → 224, matching the forced power-offs.

### memtest86+ (2026-10-02 → 2026-10-04)

Booted from the GRUB "Memory test" entry. Photo taken 2026-10-04 19:17:

- memtest86+ v7.20, 15.9 GB, DDR4-2133 CAS 15-15-15-36, CPU 35–58 °C
- **55 passes, 47 h 15 m, 0 errors, Status: Pass**

### Conclusion

| Test | Result |
|---|---|
| memtest86+, 47 h / 55 passes | 0 errors |
| Linux burn-in, 23 h RAM + CPU + cache + I/O with verification | 0 errors; froze ~30 s after a screen unlock |
| Sep 28 freeze | Kernel memory corruption while a Firefox process exited, desktop in use |

RAM, memory controller and CPU are sound under sustained load. Both freezes happened while
the **desktop/graphics path was active** (Firefox exit; DPMS wake + unlock + NVIDIA output
re-probe), never during the long unattended stress stretches. Leading suspect: the
NVIDIA 550 driver / Xorg display path. Not proven — two incidents only. Not tested: the GPU
itself and the PSU under GPU load (memtest touches neither).

Decision (user, 2026-10-04): core hardware (everything except the GPU) is considered
solid; continue the build. The GPU/display question stays open. The desktop-free burn-in
(`burnin.sh` under `multi-user.target`, transient unit started with
`-p IgnoreOnIsolate=yes` so `systemctl isolate` does not stop it) is deferred, not dropped.

Option for later: drive the display from the CPU's Intel HD 530 (in-kernel `i915`) and keep
the GTX 1050 Ti for Ollama/CUDA only, with no monitor on it. That removes the NVIDIA display
path from daily use and is itself the test: if freezes stop, that was the cause. As of
2026-10-04 the iGPU is **not on the PCI bus** (`lspci` shows only the GP107), so it is off in
BIOS; it needs enabling there (F10) and the monitor moved to the motherboard's video output.
No NVIDIA package changes are involved.

### Capture for next time

Added to `/etc/sysctl.d/90-lockup-panic.conf` on 2026-10-04 (applied, verified with
`/proc/sys/kernel/*`):

```
kernel.hung_task_panic = 1   # task stuck in D state 120 s -> panic -> pstore
kernel.panic_on_oops = 1     # an Oops like Sep 28's stops the box instead of limping
kernel.sysrq = 1             # full magic SysRq
```

`kernel.panic` stays 0, so after a panic the trace stays on screen: photograph it.

If it freezes again:

1. From another machine, `ssh ghost@192.168.1.59`. If that works, run
   `sudo dmesg -T | tail -100` and `ps -eo pid,stat,wchan:32,cmd | awk '$2 ~ /D/'`.
2. Otherwise Alt+SysRq+W (dump blocked tasks), wait 10 s, then Alt+SysRq+S, U, B
   (sync, remount read-only, reboot) instead of holding the power button.
3. After reboot: `sudo ls -R /var/lib/systemd/pstore/` and
   `journalctl -b -1 -p warning`.

**Caution before ZFS goes in:** `hung_task_panic=1` can panic the NAS during legitimately
slow I/O (a dying disk retrying, a heavy scrub). The Toshiba 1 TB still has pending sectors.
Remove that line, or raise `kernel.hung_task_timeout_secs`, before pools are imported and in
real use.

## 2026-10-04 (later): GPU removed

To get the display on the iGPU, the GTX 1050 Ti was physically removed. With the card in,
the Z240 kept the HD 530 off the PCI bus. After that boot, `lspci` shows the HD 530
(`8086:1912`) on `i915` and no NVIDIA device, and Ollama runs CPU-only. The card is still
**untested**. It returns compute-only (no display, `multi-user.target`) once the box is a
strict NAS, after the test procedure in `docs/hardware/GPU.md`. Any freeze from now on
happened without the NVIDIA card in the machine, which itself narrows the cause.
