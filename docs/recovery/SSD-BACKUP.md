# OS SSD backup: what is on the SSD and how it is protected

**Set up:** 2026-10-06. The OS SSD (Crucial MX200 250 GB, ext4 `/`) has no mirror, snapshots or copy
of its own. Everything worth keeping on it is copied onto ZFS every night.

| On the SSD | Worth keeping? | How it is protected |
|---|---|---|
| `/etc` (every config: Samba, sanoid, fstab, systemd units, sysctl…) | yes | `ssd-backup` → `/tank1tb/Backups/motherlode-ssd/etc/`; most also in this repo |
| `/home/ghost` (repo, secrets files, burn-in logs, desktop settings, Downloads) | yes | `ssd-backup` → `.../home_ghost/` (minus `.cache`, `.npm`, Trash) |
| `/root` | small | `ssd-backup` → `.../root/` |
| Installed package list | yes | `.../dpkg-selections.txt`, `.../apt-manual.txt` |
| Docker volumes (Nextcloud DB, AIO config, search index) | yes | **moved to ZFS**: `/tank1tb/Apps/docker-volumes`, bind-mounted at `/var/lib/docker/volumes` |
| Docker images, Debian packages, Ollama models, caches | no | re-downloadable |
| `/var/lib/tailscale` | no | re-login with `tailscale up` (see `docs/services/tailscale.md`) |

## The nightly chain

```text
02:30  ssd-backup.timer      rsync /etc, /root, /home/ghost → /tank1tb/Backups/motherlode-ssd   (root-only, 700)
every 15 min  sanoid.timer   snapshots: Apps hourly (docker volumes), Backups daily
03:00  syncoid-backup-tank1tb-to-tank500gb     copies Documents Photos Music Apps Nextcloud Backups → tank500gb
```

Backups keeps 14 daily / 4 weekly / 3 monthly snapshots on both pools. Because the Backups daily
snapshot is taken at 23:59 UTC (~20:00 local) and the SSD copy runs at 02:30, the snapshot holds the
previous night's copy; the tank500gb copy of Backups is therefore about a day behind. Fine for configs.

Files: `scripts/backup/ssd-backup.sh` → `/usr/local/sbin/ssd-backup`,
`systemd/ssd-backup.{service,timer}` → `/etc/systemd/system/`.

```bash
sudo systemctl start ssd-backup         # run now
sudo journalctl -u ssd-backup -n 20     # last run
sudo systemctl disable --now ssd-backup.timer   # turn off
```

The copy contains secrets (Nextcloud backup codes and AIO passphrase in `home_ghost/homelab/`,
Tailscale nothing, SSH host keys in `etc/ssh/`). It is root-only and `tank1tb/Backups` is not a
Samba share or Nextcloud mount. It is not encrypted.

## Rebuild after an SSD failure

1. Install Debian 13, then ZFS (`zfs/README.md`), import the pools (`zpool import -f -d /dev/disk/by-id ...`).
2. Copy back what you need from `/tank1tb/Backups/motherlode-ssd/` (or `/tank500gb/Backups/...`,
   or an older `.zfs/snapshot/<snap>/`): the home folder, then configs file by file. Don't blindly
   copy all of `etc/` over a fresh install; use it as the reference.
3. Reinstall packages: `sudo apt install $(cat apt-manual.txt)` (check the list first).
4. Docker: install (`docs/services/docker.md`), restore the fstab bind line for
   `/var/lib/docker/volumes`, start Docker, then `docker compose up -d` in `nextcloud/`. The volumes
   (database, AIO config) are already on ZFS, so Nextcloud comes back as it was.
5. Tailscale: reinstall and log in.

## History

- 2026-10-06: Docker volumes moved from the SSD to ZFS. Docker stopped (AIO stop first, which
  dumps the database), volumes copied with `rsync -aHAX --numeric-ids` (42,396 entries; checksum
  check found only files Docker rewrote on restart), old copy kept as
  `/var/lib/docker/volumes.ssd-old-2026-10-06` until the move has run a few days, then delete it.
  `docker.service` got a drop-in, `RequiresMountsFor=/var/lib/docker/volumes`, so it can never
  start with an empty volumes folder on the SSD.

## Verification (2026-10-06)

| Check | Result |
|---|---|
| `ssd-backup` first run | `/etc`, `/root`, `/home/ghost` copied, 718 MB, service exit 0 |
| Docker on ZFS | `findmnt /var/lib/docker/volumes` → `tank1tb/Apps[/docker-volumes]`; all 9 Nextcloud containers healthy afterwards |
| Reached tank500gb | manual snapshots `tank1tb/Apps@first-zfs-volumes`, `tank1tb/Backups@first-ssd-backup` + `syncoid-backup-tank1tb-to-tank500gb`: `tank500gb/Apps` 833 MB with every `nextcloud_aio_*` volume, `tank500gb/Backups` 703 MB with `motherlode-ssd/{etc,home_ghost,root}` |

The two manual snapshots are not pruned by sanoid (only `autosnap_*` are); delete them once newer
automatic ones exist on both pools.
