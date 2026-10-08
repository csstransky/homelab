# Backups, snapshots and disk checks (Checkpoint 3)

**Set up and tested:** 2026-10-04.
Visual walk-through: open `zfs/backups-explained.html` in a browser.

## The layers

| Layer | Protects against | Tool | Status |
|---|---|---|---|
| 1. Mirror | One disk dying | ZFS (`tank1tb`, `tank500gb`) | running since 2026-09-27 |
| 2. Snapshots | Deleted or overwritten files, ransomware arriving through SMB | `sanoid` | running, tested |
| 3. Nightly copy | Losing the whole `tank1tb` pool (both disks, corruption, `zfs destroy`) | `syncoid` → `tank500gb` | running, tested |
| 4. Scrubs + SMART tests | Silent decay; spotting a dying disk early | `zfs-scrub-monthly@`, `smartd` | scheduled |
| 5. Off-site, encrypted copy | Fire, theft, surge, root compromise | not chosen yet | **Checkpoint 11** |

Layers 1–4 all live in one box. Only layer 5 completes the 3-2-1 rule (3 copies, 2 kinds of
media, 1 off-site). Until then this is good protection from mistakes and disk failures, not a full backup.

## Why these numbers

No standard prescribes retention counts; they describe practice. Sources consulted 2026-10-04:

- CISA: 3-2-1, offline/encrypted copies, test restores, be able to roll back at least 7 days.
  <https://www.cisa.gov/audiences/small-and-medium-businesses/secure-your-business/back-up-business-data>
- NIST SP 800-209 (storage security): snapshots depend on their source; test backups regularly.
  <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-209.pdf>
- Grandfather-father-son rotation: many recent copies, fewer old ones.
  <https://en.wikipedia.org/wiki/Backup_rotation_scheme>
- Sanoid's own templates (production 36h/30d/4w/3m; backup target 30h/90d/4w/12m) and homelab
  write-ups landing on roughly 24–36 hourly, 30 daily, 6–12 monthly.
  <https://github.com/jimsalterjrs/sanoid/blob/master/sanoid.conf>
- There is no IEEE standard for backup retention. ISO/IEC 27001 (A.8.13) requires a backup policy
  and restore testing but sets no numbers.

## Snapshot policy (sanoid)

Config: `/etc/sanoid/sanoid.conf` (repo copy `zfs/sanoid.conf`). `sanoid.timer` runs every 15
minutes: it takes a snapshot when one of a kind is due, and prunes down to the counts below.
Each number is **how many to keep**.

| Dataset | Hourly | Daily | Weekly | Monthly | Oldest snapshot |
|---|---|---|---|---|---|
| Documents, Photos, Nextcloud, Apps | 24 | 30 | 8 | 12 | ~1 year |
| Music | 0 | 30 | 4 | 6 | ~6 months |
| Backups | 0 | 14 | 4 | 3 | ~3 months |
| `media` pool | — | — | — | — | not snapshotted (disposable) |
| `/other` | — | — | — | — | ext4, cannot be snapshotted |

Timing (sanoid defaults): hourly at :00, daily 23:59, weekly Monday 23:30, monthly on the 1st
00:00. These are **UTC**: Debian's `sanoid.service` sets `TZ=UTC`, so snapshot names read 4–5 h
ahead of local time (`autosnap_2026-10-05_02:00:11_hourly` was taken 22:00 EDT on 10-04).

Space: a snapshot only holds blocks changed since it was taken. **A deleted file keeps using space
until the last snapshot that contains it expires, up to 12 months.** To reclaim space sooner,
destroy the relevant snapshots by hand (`zfs list -t snapshot`, then `zfs destroy <name>`; read the
name twice).

## Nightly copy to tank500gb (syncoid)

| Item | Value |
|---|---|
| Datasets | `Documents`, `Photos`, `Music`, `Apps`, `Nextcloud`, `Backups` (Backups added 2026-10-06) |
| Target | `tank500gb/<name>`, mounted read-only at `/tank500gb/<name>` |
| When | 03:00 local, `syncoid-backup-tank1tb-to-tank500gb.timer` (`Persistent=true`: runs at boot if 03:00 was missed) |
| Script | `/usr/local/sbin/syncoid-backup-tank1tb-to-tank500gb` (repo `scripts/backup/syncoid-backup-tank1tb-to-tank500gb.sh`) |
| Units | `/etc/systemd/system/syncoid-backup-tank1tb-to-tank500gb.{service,timer}` (repo `systemd/`) |
| Logs | `sudo journalctl -u syncoid-backup-tank1tb-to-tank500gb` |

How it works: `syncoid --no-sync-snap --create-bookmark tank1tb/X tank500gb/X` for each dataset.
It sends only sanoid's snapshots made since the last run (ZFS incremental send: only changed
blocks). The bookmark lets the next run stay incremental even if sanoid has pruned the snapshot it
last sent. On tank500gb, sanoid takes **no** snapshots (`autosnap = no`); it only prunes the
received ones to the same counts as the source (`template_replica_*`). One failing dataset does not
stop the others; the service then exits with an error.

Capacity: tank500gb has ~450 GB against ~899 GB on tank1tb. Fine today (MB used). When the
copied datasets approach ~400 GB together, decide what to drop from the list in the script.

### Turn it off / on / run now

```bash
sudo systemctl disable --now syncoid-backup-tank1tb-to-tank500gb.timer    # stop nightly copies (existing copies stay)
sudo systemctl enable --now syncoid-backup-tank1tb-to-tank500gb.timer     # resume
sudo systemctl start syncoid-backup-tank1tb-to-tank500gb.service          # copy right now
systemctl list-timers sanoid.timer syncoid-backup-tank1tb-to-tank500gb.timer 'zfs-scrub*'
```

Snapshots: `sudo systemctl disable --now sanoid.timer` stops both taking and pruning.
Retention changes: edit `/etc/sanoid/sanoid.conf`; picked up on the next 15-minute run.

Why systemd timers and not cron: Debian already ships `sanoid.timer`; timers catch up after
downtime (`Persistent=true`), never start a second copy while one runs, log to the journal, and all
schedules show in `systemctl list-timers`. Debian's `/etc/cron.d/sanoid` is a fallback that only
runs on machines without systemd.

## Off the SSD (2026-10-06)

Two additions so nothing important lives only on the unmirrored OS SSD:

- **Docker volumes** (Nextcloud database, AIO config, search index) moved to
  `/tank1tb/Apps/docker-volumes`, bind-mounted at `/var/lib/docker/volumes`. They get the Apps
  snapshots (hourly) and the nightly copy.
- **`ssd-backup.timer` at 02:30** copies `/etc`, `/root` and `/home/ghost` to
  `/tank1tb/Backups/motherlode-ssd/`, and `Backups` joined the 03:00 copy
  (`template_replica_backups`: 14 daily, 4 weekly, 3 monthly).

Details and SSD rebuild steps: `docs/recovery/SSD-BACKUP.md`.

### Missed copies after a crash

The 21:08 boot on 2026-10-06 started a catch-up copy (`Persistent=true`, 03:00 was missed during
memtest). The 21:12 panic killed it mid-Photos, and a timer counts a run as done when it **starts**,
so nothing retried until the next 03:00. `tank500gb/Music` was still empty and Photos at 11.5 of
40 GB. After any crash, start a copy by hand: `sudo systemctl start syncoid-backup-tank1tb-to-tank500gb`.
syncoid resumes an interrupted receive.

### Killed by the bait test (2026-10-08)

The first run under the new name (13:30, started by hand to test the rename from
`syncoid-tank500gb`) lost `Apps` at 13:40:25: `Terminated`, `cannot receive: failed to read from
stream`. Cause: the RAM bait test (`scripts/diagnostics/bait-crash.sh`) reached its 8 h runtime at
13:39:57 and its cleanup runs `pkill -f "zfs send .*@autosnap"` to stop its own test sends. That
pattern also matches this backup's `zfs send ... tank1tb/Apps@autosnap_...`. Photos, Documents
and Music had already copied. A rerun at 13:43, after the bait test had finished, resumed Apps from
where it stopped (51 MB of the 142 MB left) and exited 0. **Don't run a backup while a bait test is running or ending**, and
narrow that `pkill` to the bait script's own processes before the next bait run (not done while
the 2026-10-08 run was still in its cleanup: editing a running bash script can break it).
**Fixed 2026-10-08:** cleanup now kills only the script's own process tree and cancels only the
scrubs it started; tested with a decoy `zfs send ...@autosnap` process, which survived.

## Restoring

**One file, from a snapshot** (fastest). Every snapshot is a read-only folder:

```bash
ls /tank1tb/Documents/.zfs/snapshot/                       # one folder per snapshot (UTC names)
cp -a /tank1tb/Documents/.zfs/snapshot/<snap>/path/file /tank1tb/Documents/path/
```

**From the tank500gb copy**, if tank1tb is gone: browse `/tank500gb/Documents/` (latest) or
`/tank500gb/Documents/.zfs/snapshot/<snap>/` (older), and copy out.

**Whole dataset back in time** (destroys everything newer than the snapshot; only after copying out
anything newer you want): `zfs rollback -r tank1tb/Documents@<snap>`.

## Scrubs

`zfs-scrub-monthly@{tank1tb,tank500gb,media}.timer` (Debian units): 1st of the month around 00:00
plus up to 1 h random delay, `Persistent=true`. Check results with `zpool status`.

## SMART self-tests (smartd)

`/etc/smartd.conf` (original kept as `/etc/smartd.conf.debian-default`):

```text
DEVICESCAN -d removable -n standby -s (S/../../7/02|L/../15/./04) -W 4,45,55 -m root -M exec /usr/share/smartmontools/smartd-runner
```

Short test every Sunday 02:00, long test on the 15th at 04:00 (away from the scrubs on the 1st).
Temperature changes of 4 °C are logged, 45 °C is info, 55 °C critical. Mail (`-m root`) goes nowhere
until there is a mail transfer agent (Checkpoint 13). Read results with
`sudo journalctl -t smartd` and `sudo smartctl -l selftest /dev/disk/by-id/<disk>`. The service is
`smartmontools.service`.

## Verification (2026-10-04)

| Check | Result |
|---|---|
| `sanoid.service` first run | 22 snapshots across the 6 tank1tb datasets (one per tier) |
| Scheduled snapshot | `tank1tb/Documents@autosnap_2026-10-05_02:00:11_hourly` taken by the timer at 22:00 EDT |
| Restore | Test file written 21:44, captured by the 22:00 snapshot, deleted, copied back from `.zfs/snapshot/`: contents, owner `ghost:nas` and mtime identical |
| First syncoid run | Full send of 5 datasets, `rc=0`; targets `readonly=on`; bookmarks on the source |
| Second syncoid run | Incremental only (`01:44 ... 02:00`, ~33 KB Documents, ~4 KB others); Music "nothing to do" |
| Replica | Test file readable in `/tank500gb/Documents`; `touch` there fails: `Read-only file system` |
| Scrubs | Manual scrub of all three pools 0 errors (Checkpoint 2); monthly timers enabled, next 2026-11-01 |
| smartd | Config parses; restarted; first scheduled short test Sunday 2026-10-11 02:00 |
| Prune | `sanoid --prune-snapshots --readonly`: nothing to prune yet (counts not reached); real pruning starts once 25 hourlies exist |

## Toshiba long test (2026-10-04)

`smartctl -t long` on `ata-TOSHIBA_DT01ACA100_Z5B2VRDNS` stopped within minutes:
`Extended offline  Completed: read failure  90%  22148  1904285592`. The same LBA (908 GiB in,
inside the ZFS partition) has failed every self-test since hour 22058. The drive cannot finish a
surface test while that sector is unreadable. Still 24 pending / 24 offline-uncorrectable sectors,
0 reallocated. ZFS has seen no errors from it (nothing is stored there yet).

Options, in order of preference:

1. **Replace the Toshiba** with a new ≥1 TB disk: `zpool replace tank1tb <toshiba-by-id> <new-by-id>`,
   pool stays online while it resilvers from the WD.
2. Force the drive to remap the bad sectors by writing over them (e.g. `hdparm --write-sector`
   on each failing LBA, then a scrub repairs any ZFS block there from the WD copy). This destroys
   whatever is in those sectors and needs explicit confirmation per AGENTS.md rule 1.
3. Leave it: the mirror plus the nightly copy cover a failure, but it is the weakest disk in the pool.
