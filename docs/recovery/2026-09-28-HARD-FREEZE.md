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
