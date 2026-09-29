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
  `sudo ls /sys/fs/pstore/` and `sudo cat /sys/fs/pstore/dmesg-*`.
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
