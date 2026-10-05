# ZFS on MOTHERLODE

**Pools created:** 2026-09-27 (previous Debian install, see `zpool history`).
**Re-imported:** 2026-10-04 on the current Debian 13 install (Checkpoint 2).

Visual walk-through (disk map, pool roles, settings, boot order, every command): open
`zfs/zfs-explained.html` in a browser.

Software: `zfs-dkms` + `zfsutils-linux` 2.3.9 from Debian `contrib`. Secure Boot stays
disabled so the DKMS module loads unsigned. The ZFS DKMS build was running when the
2026-09-28 hard freeze hit (`docs/recovery/2026-09-28-HARD-FREEZE.md`); `dpkg --configure -a`
finished it cleanly.

## Pools

| Pool | Layout | Size | Mountpoint | Role |
|---|---|---|---|---|
| `tank1tb` | mirror | 928G | `/tank1tb` | Primary important data |
| `tank500gb` | mirror | 464G | `/tank500gb` | Backup / replication target |
| `media` | single disk | 1.81T | `/media` | Disposable media only |

Members (always by-id, never `/dev/sdX`; drive letters change between boots):

| Pool | Member |
|---|---|
| `tank1tb` | `ata-WDC_WD10EZEX-60M2NA0_WD-WCC3F2CYKRSN-part1` |
| `tank1tb` | `ata-TOSHIBA_DT01ACA100_Z5B2VRDNS-part1` |
| `tank500gb` | `ata-WDC_WD6400AAKS-00A7B2_WD-WCASYD471432-part1` |
| `tank500gb` | `ata-ST500DM002-1BD142_W2AF3DHD-part1` |
| `media` | `ata-ST2000DX002-2DV164_Z4ZB3346-part1` |

The WD 640 GB also holds `/other` on `-part2` (ext4, below). The OS SSD
(`ata-Crucial_CT250MX200SSD1_154511053F30`) is never touched.

## Datasets

```text
tank1tb/Documents   /tank1tb/Documents
tank1tb/Photos      /tank1tb/Photos
tank1tb/Music       /tank1tb/Music      important music library
tank1tb/Backups     /tank1tb/Backups
tank1tb/Nextcloud   /tank1tb/Nextcloud  NOT a Samba share
tank1tb/Apps        /tank1tb/Apps       persistent container data
```

`media` has no child datasets. `tank500gb` holds read-only copies of Documents, Photos, Music,
Apps and Nextcloud, made nightly by syncoid (`zfs/BACKUPS.md`). `/media/Movies`, `/media/TV` and
`/media/Music` are plain directories. `/media/ghost` is a leftover udisks automount
directory from the old install.

## Properties

All three pools were created with the same options:

```bash
zpool create -o ashift=12 -o cachefile=/etc/zfs/zpool.cache \
  -O acltype=posixacl -O xattr=sa -O compression=lz4 -O dnodesize=auto -O relatime=on \
  -O mountpoint=/<pool> <pool> [mirror] /dev/disk/by-id/<member>-part1 ...
```

Datasets inherit everything from their pool. `autotrim` is off (all spinning disks).

## Ownership left over from the old install

`/tank1tb/{Documents,Photos,Music}`, `/media` and its subdirectories, and `/other` are
`root:1001` mode `2775` (setgid). GID 1001 was the old `nas` group, which does not exist
on this install yet. **Create `nas` with GID 1001 in Checkpoint 4** (`groupadd -g 1001 nas`)
so these directories pick up the right group without a recursive `chgrp`.

Contents on 2026-10-04: essentially empty (about 1.5 MB on `tank1tb`, one directory under
`Documents`). No real data has been written yet.

## `/other` (ext4, not ZFS)

| Item | Value |
|---|---|
| Device | `ata-WDC_WD6400AAKS-00A7B2_WD-WCASYD471432-part2` |
| Label / UUID | `other` / `5250af8d-6988-4201-9c8c-bedd00c234b1` |
| Size | 128G |
| fstab | `UUID=5250af8d-6988-4201-9c8c-bedd00c234b1 /other ext4 defaults,noatime 0 2` |

On 2026-10-04 a read-only `e2fsck -fn` was clean apart from an unreplayed journal
(`needs_recovery`): the old install powered off with it mounted. The first mount replayed
it (`EXT4-fs (sde2): recovery complete`).

## Boot

`zfs-import-cache.service` imports every pool listed in `/etc/zfs/zpool.cache`, then
`zfs-mount.service` mounts them. Enabled units: `zfs-import-cache`, `zfs-import.target`,
`zfs-mount`, `zfs-zed`, `zfs-share`, `zfs-volume-wait`, `zfs.target`.
`zfs-import-scan` stays disabled. Snapshots, the nightly copy, scrub timers and SMART tests:
`zfs/BACKUPS.md` (Checkpoint 3).

Debian's installer put the DVD drive at `/dev/sr0 /media/cdrom0`, inside the `media` pool's
mountpoint. The line now points at `/mnt/cdrom`, and the empty `/media/cdrom0` directory and
`/media/cdrom` symlink were removed, so the pool mounts on an empty `/media`. Keep anything
non-ZFS out of `/media`. Backup of the original: `/etc/fstab.bak-2026-10-04`.

## Import procedure (fresh OS install, or pools missing after boot)

```bash
sudo apt install zfs-dkms zfsutils-linux      # contrib; Secure Boot off
sudo modprobe zfs
sudo zpool import                              # scan only: lists pools, changes nothing
for p in tank1tb tank500gb media; do
  sudo zpool import -d /dev/disk/by-id -o cachefile=/etc/zfs/zpool.cache "$p"
done
zpool status; zfs list
```

**When `-f` is needed:** after an OS reinstall the pools report *"last accessed by another
system"* (ZFS-8000-EY). The new install has a new `/etc/hostid` (here `017c5e3e`), so the old
hostid stored in the pool no longer matches. That is the only time `-f` is right. Check
first that no other machine can see these disks. On 2026-10-04 all three pools needed
`-f` for this reason.

If a pool is already imported but missing from the cachefile:
`sudo zpool set cachefile=/etc/zfs/zpool.cache <pool>`.

A mirror with one member missing imports `DEGRADED`. That is fine for reading data. Do not
`zpool replace` or `detach` until the missing disk is identified by-id.

## Drive health notes

- **Toshiba DT01ACA100** (`tank1tb` member): 24 pending / 24 offline-uncorrectable sectors,
  and short self-tests fail reading LBA 1904285592 (about 908 GiB into a 931.5 GiB disk).
  The 2026-10-04 scrubs finished in seconds with 0 errors, but they only read allocated
  blocks and the pools are nearly empty, so the bad area was **not** exercised. ZFS repairs
  it from the WD side when data lands there. On 2026-10-04 a SMART long test stopped at that
  same LBA (`Completed: read failure`), so the drive cannot complete a surface test. Plan to
  replace it (`zfs/BACKUPS.md`).
- **Seagate ST2000DX002** (`media`): clean now, but it has a history of UNC read errors.
  Disposable data only.

## Memory (ARC)

ZFS caches reads in RAM (the ARC). On this box the ceiling is `c_max` = 14.4 GB of 16 GB
(`/proc/spl/kstat/zfs/arcstats`). The ARC shrinks under memory pressure, but once Ollama and
Docker run alongside, consider capping it (e.g. `options zfs zfs_arc_max=<bytes>` in
`/etc/modprobe.d/zfs.conf`). **Capped at 8 GiB on 2026-10-04** (`options zfs zfs_arc_max=8589934592`
in `/etc/modprobe.d/zfs.conf`, initramfs updated) to leave room for Nextcloud and Jellyfin.
The live shrink exposed a memory fault and the kernel panicked (`docs/recovery/2026-10-04-ZFS-PANIC.md`);
the cap itself is not the cause.

## Verification (2026-10-04)

```text
$ zpool status         all three ONLINE, 0 READ/WRITE/CKSUM, "No known data errors"
$ zpool scrub ...      tank1tb, tank500gb, media: repaired 0B with 0 errors
$ zfs list             all datasets mounted at the paths above
$ findmnt /other       /dev/sde2 ext4 rw,noatime
```
