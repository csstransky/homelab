# Nextcloud (Checkpoint 8)

**Running and tested from the public internet:** 2026-10-06.
Visual walk-through: `nextcloud/nextcloud-explained.html`.

Nextcloud is the "own Google Drive": web UI, phone app with auto-upload, desktop sync,
share links, online editing (Collabora) and full-text search, over the **same folders**
Windows sees through Samba. There is one copy of every file.

## Address and access

| What | Address | Who can reach it |
|---|---|---|
| Nextcloud | **https://motherlode.tailb6c0f2.ts.net** | **Anyone on the internet** (Tailscale Funnel) |
| AIO admin interface | `https://192.168.1.59:8080` (use the IP; self-signed cert) | LAN and tailnet only |
| Nextcloud direct | `127.0.0.1:11000` | MOTHERLODE only (Funnel's target) |

Accounts: `admin` (password changed by the user, 2FA via Duo Mobile TOTP, backup codes kept
outside git). Secrets never go in the repo: `.gitignore` has `*backup-codes*`, `*passphrase*`,
`*password*`. The local files `Nextcloud-backup-codes.txt` and `.nextcloud-passphrase.txt` in the
repo folder are ignored and `chmod 600`. Keep copies in a password manager.

## Versions and containers (AIO v14.2.0, Nextcloud 34.0.4 "Hub 26 Spring")

| Container | Role | RAM seen |
|---|---|---|
| mastercontainer | AIO itself: creates, updates, starts and stops the others | 73 MB |
| apache | Caddy + Apache, the web front on port 11000 | 99 MB |
| nextcloud | PHP app | 595 MB |
| database | PostgreSQL | 122 MB |
| redis | cache, file locking | 7 MB |
| notify-push | instant change notifications to clients | 7 MB |
| collabora | **Nextcloud Office** (Collabora Online), edit docx/xlsx/odt in the browser | 418 MB |
| imaginary | previews for HEIC, PDF, SVG, TIFF, WebP | 144 MB |
| fulltextsearch | Elasticsearch, search inside documents | 728 MB |

Not enabled: Talk (needs public port 3478, impossible through Funnel), ClamAV (~1 GB RAM),
Whiteboard, Docker Socket Proxy/HaRP. All can be added later in the AIO interface.

## How a request gets in

```text
phone / browser, anywhere
  → https://motherlode.tailb6c0f2.ts.net  (public DNS → Tailscale Funnel relays, TLS cert from Tailscale)
  → tailscaled on MOTHERLODE
  → http://127.0.0.1:11000  (nextcloud-aio-apache)
  → nextcloud-aio-nextcloud  (+ collabora, imaginary, fulltextsearch, redis, database, notify-push)
  → files: /srv/nas/<Share>  =  the Samba shares
```

Devices on the tailnet reach the same name directly (not through Funnel's relays).

Funnel commands:

```bash
tailscale funnel status
tailscale funnel --https=443 off      # take Nextcloud off the internet (tailnet still works via serve)
tailscale funnel --bg 11000           # put it back
```

## One folder per kind of file (External Storage)

User decision 2026-10-04: no second Pictures or Documents inside Nextcloud. Every Samba share is
attached to Nextcloud with the **External Storage** app ("Local" type):

| Mount | Host path | Samba share | Snapshots / nightly copy |
|---|---|---|---|
| /Pictures | `/srv/nas/Pictures` = `/tank1tb/Pictures` | Pictures | yes / yes |
| /Documents | `/srv/nas/Documents` = `/tank1tb/Documents` | Documents | yes / yes |
| /Music | `/srv/nas/Music` = `/tank1tb/Music` | Music | yes / yes |
| /Media | `/srv/nas/Media` = `/media` | Media | no (disposable by design) |
| /Other | `/srv/nas/Other` = `/other` (ext4) | Other | no (ext4, not ZFS) |

- **`/srv/nas`**: AIO lets Nextcloud see exactly one host folder (`NEXTCLOUD_MOUNT`). `/srv/nas`
  holds a **bind mount** of each share (fstab; the same files at a second path, not copies), so all
  five fit under one folder. `/etc/fstab.bak-2026-10-06` is the copy from before.
- Mounts apply to user `admin`, sharing enabled, "check for changes" = on every access, so files
  added over Samba show up in Nextcloud.
- `/tank1tb/Nextcloud` (`NEXTCLOUD_DATADIR`) holds only Nextcloud's internal data (`admin/`,
  `appdata_*`). It is not a Samba share. **Never change `NEXTCLOUD_DATADIR` after install.**
- `lost+found` (root-only folder on the ext4 `/other` disk) is hidden from Nextcloud with
  `occ config:system:set forbidden_filenames 1 --value=lost+found` (index 0 stays `.htaccess`). Before
  that, every scan of Other failed on it (`opendir(...lost+found): Permission denied`), marked the
  storage "not available", and left Other's size at -1.
- Files added over Samba appear in Nextcloud when a folder is opened (check-on-access), but a
  brand-new folder can show **-1 B** (size not computed yet) until it is opened or scanned:
  `occ files:scan --path="/admin/files/Other"`. Windows Explorer, in turn, often does not refresh a
  network folder by itself, especially during a big copy into it: press F5.
- Check-on-access updates the file index, **not previews**: a file *replaced* over Samba keeps its
  old thumbnail in Nextcloud. `nextcloud-fix-stale-previews.timer` clears those every 15 minutes; run
  `nextcloud-fix-stale-previews` to do it now (`docs/recovery/2026-10-08-STALE-NEXTCLOUD-PREVIEWS.md`).
- `/media/ghost` is where XFCE auto-mounts USB drives. It is left without Nextcloud permissions, so
  USB drives don't appear in Nextcloud.

### Permissions (POSIX ACLs)

Nextcloud runs as `www-data` (uid 33). Samba writes as `ghost` with group `nas`. Each share has:

```text
user:www-data:rwx   group:nas:rwx   default:user:www-data:rwx   default:group:nas:rwx
```

The `default:` entries make new files and folders inherit both, whichever side creates them.
Checked: a file created as `ghost` gets `www-data` rw; a file created by Nextcloud is
`www-data:nas rw-rw-r--` (setgid folders keep group `nas`). All existing entries were
updated: Pictures 13,432, Documents 92,933, Music 8,919, Media 4, Other 6.

### Adding a new share later

```bash
# 1. the folder (ZFS dataset or plain folder), group nas, setgid
sudo zfs create tank1tb/NewThing && sudo chgrp nas /tank1tb/NewThing && sudo chmod 2775 /tank1tb/NewThing
# 2. Samba: add a [NewThing] block like the others in /etc/samba/smb.conf (+ repo samba/smb.conf), then:
sudo systemctl reload smbd
# 3. Nextcloud permissions (ACLs) on everything in it, and inherited by new files
sudo setfacl -R -m u:33:rwX,g:nas:rwX /tank1tb/NewThing
sudo find /tank1tb/NewThing -type d -exec setfacl -m d:u::rwx,d:g::rwx,d:o::rx,d:u:33:rwx,d:g:nas:rwx {} +
# 4. make it visible under /srv/nas (add the same line to /etc/fstab)
sudo mkdir /srv/nas/NewThing
echo '/tank1tb/NewThing /srv/nas/NewThing none bind,x-systemd.requires=zfs-mount.service 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/nas/NewThing
# 5. restart Nextcloud so its container sees the new bind (AIO stop + start)
docker exec nextcloud-aio-mastercontainer /daily-backup.sh                         # stops
docker exec --env START_CONTAINERS=1 nextcloud-aio-mastercontainer /daily-backup.sh # starts
# 6. attach it in Nextcloud
OCC='docker exec --user www-data nextcloud-aio-nextcloud php occ'
$OCC files_external:create /NewThing local null::null -c datadir=/srv/nas/NewThing   # prints the mount id
$OCC files_external:applicable --add-user admin <id>
$OCC files_external:option <id> enable_sharing true
$OCC files_external:scan <id>   # or: $OCC files:scan admin
# 7. snapshots/nightly copy: add it to zfs/sanoid.conf and scripts/backup/syncoid-backup-tank1tb-to-tank500gb.sh
```

### Renaming a share later

Nextcloud names a Local storage after its path (`local::/srv/nas/Old/`), so changing `datadir` with
`occ` makes a new storage: everything is re-indexed and favourites are lost (see the cleanup below).
Rename the storage row instead, and file ids, favourites and previews stay. Tested 2026-10-09:
`files:scan` afterwards found 0 new, 0 removed, and the folder kept its file id and 11 favourites.

```bash
# stop what touches it; snapshot the Nextcloud database (Docker volumes) for undo
sudo systemctl stop sanoid.timer syncoid-backup-tank1tb-to-tank500gb.timer nextcloud-fix-stale-previews.timer
sudo docker exec --user www-data nextcloud-aio-nextcloud php occ maintenance:mode --on
sudo docker stop nextcloud-aio-nextcloud && sudo systemctl stop smbd
sudo zfs snapshot tank1tb/Apps@pre-rename
# rename the dataset (snapshots go with it) and its nightly copy
sudo umount /srv/nas/Old
sudo zfs rename tank1tb/Old tank1tb/New && sudo zfs rename tank500gb/Old tank500gb/New
# edit Old → New in /etc/fstab, /etc/samba/smb.conf, /etc/sanoid/sanoid.conf,
# scripts/backup/syncoid-backup-tank1tb-to-tank500gb.sh (then install it to /usr/local/sbin)
sudo rmdir /srv/nas/Old && sudo mkdir /srv/nas/New && sudo systemctl daemon-reload && sudo mount /srv/nas/New
sudo systemctl start smbd
# Nextcloud: rename the storage, the mount and its path in one transaction (<id> = files_external:list)
sudo docker exec -i nextcloud-aio-database psql -U oc_nextcloud -d nextcloud_database <<'SQL'
begin;
update oc_storages set id = 'local::/srv/nas/New/' where id = 'local::/srv/nas/Old/';
update oc_external_mounts set mount_point = '/New' where mount_id = <id>;
update oc_external_config set value = '/srv/nas/New' where mount_id = <id> and key = 'datadir';
update oc_mounts set mount_point = '/admin/files/New/' where mount_point = '/admin/files/Old/';
commit;
SQL
sudo docker start nextcloud-aio-nextcloud      # also makes the container see the new bind mount
sudo docker exec --user www-data nextcloud-aio-nextcloud php occ maintenance:mode --off
sudo docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --path="/admin/files/New"   # expect 0 new, 0 removed
sudo systemctl start sanoid.timer syncoid-backup-tank1tb-to-tank500gb.timer nextcloud-fix-stale-previews.timer
```

Windows: `net use X: /delete`, then map the new share name. A mount hides whatever sits at the same
path in admin's own files (`/tank1tb/Nextcloud/admin/files/`, e.g. Nextcloud's sample folders), so
after a rename those can appear next to the new name.

## Security (the login page is public)

| Layer | Setting | Checked |
|---|---|---|
| HTTPS | Tailscale Funnel certificate for `*.ts.net` | browser padlock |
| Password | changed from the AIO-generated one | user |
| **Two-factor** | `twofactorauth:enforce --on` for every account; TOTP (user uses Duo Mobile) + backup codes | login from phone asked for the code |
| Brute-force throttling | built in, **per real client IP** | failed test login was throttled under `100.111.72.91`, not the proxy |
| Real visitor IPs | Funnel and Caddy pass `X-Forwarded-For`; Nextcloud trusts `127.0.0.1`, `::1`, `172.19.0.0/16` | phone on 5G logged as `2600:387:f:5f33::8` and `166.198.25.32` (carrier IPs) |
| Audit log | `admin_audit` app (AIO enables it): every login, failure, file access and share with IP | `/var/www/html/data/audit.log` in the container |
| Admin interface | port 8080 not funneled; nothing port-forwarded on the router | `tailscale funnel status` lists only 443 → 11000 |

Who logged in, from where:

```bash
nextcloud-show-logins    # last 30 successful/failed logins with IP (repo scripts/diagnostics/nextcloud-show-logins.sh)
nextcloud-show-logins 50 --failed
```

The audit log was 48 MB after the first scan (it logs every file touched) and is not trimmed
by `log_rotate_size` (10 MB, main log only). Keep an eye on it in Checkpoint 13.

## Where its data lives and how it is backed up

| Data | Location | Protection |
|---|---|---|
| Your files | the shares (`/tank1tb/...`, `/media`, `/other`) | Samba-side backup plan (`zfs/BACKUPS.md`) |
| Nextcloud internal data | `/tank1tb/Nextcloud` | snapshots + nightly copy |
| Database, AIO config, search index, app code | Docker volumes, **on ZFS** at `/tank1tb/Apps/docker-volumes` (bind-mounted to `/var/lib/docker/volumes`, since 2026-10-06) | snapshots (Apps: hourly) + nightly copy |
| Container images | SSD `/var/lib/docker` | none needed (re-downloadable) |

ZFS snapshots of a running Postgres are crash-consistent (all files frozen at the same instant), which
Postgres recovers from like after a power cut. AIO's own Borg backup (AIO interface → Backup and
restore) would add application-consistent backups; not set up yet.

## Everyday commands

```bash
OCC='docker exec --user www-data nextcloud-aio-nextcloud php occ'
$OCC status
$OCC files_external:list
$OCC files:scan admin                 # pick up changes made outside Nextcloud (normally automatic)
nextcloud-fix-stale-previews          # old thumbnail after replacing a file outside Nextcloud (scripts/maintenance/nextcloud-fix-stale-previews.sh)
$OCC twofactorauth:state admin
$OCC security:bruteforce:attempts <ip>
$OCC security:bruteforce:reset <ip>
docker exec nextcloud-aio-mastercontainer /daily-backup.sh                          # stop all
docker exec --env START_CONTAINERS=1 nextcloud-aio-mastercontainer /daily-backup.sh  # start all
```

Updates: AIO interface → "Stop containers" → "Start and update containers" (or set up daily
automatic updates with backups later).

## Verification (2026-10-06)

| Check | Result |
|---|---|
| All containers | healthy (9) |
| `status.php` via public URL | `installed:true, version 34.0.4` |
| Phone, Nextcloud Android app 35.0.1, Tailscale off, 5G | logged in with 2FA, browsed files; audit log shows public carrier IPs |
| Browser on ZEPHYR (Firefox 157) and on MOTHERLODE | logged in |
| External storage | 5 mounts, `files_external:verify` status ok on all |
| First scan (Pictures, Documents under `/tank1tb`) | 106,364 entries (41,425 files, 65,009 folders), 0 errors, 11 min 29 s |
| Rescan after the move to `/srv/nas` | Pictures 13,452 · Documents 92,932 · Music 8,919 · Media 5 · Other 7 entries (~35 min, during the 95 GB tank500gb copy) |
| Write test as www-data | file created in Pictures as `www-data:nas rw-rw-r--` |
| Collabora | `richdocuments:activate-config` → WOPI at `nextcloud-aio-apache:23973`, public URL autodetected |
| Full-text search | `fulltextsearch:test` passed |
| Brute force | test failure from `100.111.72.91` recorded with delay 200 ms, then reset |

## Cleanup of the old index (2026-10-06, user-approved)

Changing the mounts' paths from `/tank1tb/...` to `/srv/nas/...` made Nextcloud treat them as new
storages, leaving the old index behind (storage 3 `local::/tank1tb/Pictures/`, storage 4
`local::/tank1tb/Documents/`). `occ files:cleanup` alone skips them because the storage rows still
exist. Done with the user's explicit go-ahead, after `zfs snapshot tank1tb/Apps@pre-nc-storage-cleanup`:

```sql
-- move favourites to the same path on the new storage (3→8 Pictures, 4→9 Documents): UPDATE 7
update oc_vcategory_to_object o set objid = n.fileid from oc_filecache old
  join oc_filecache n on n.path = old.path and n.storage = (case old.storage when 3 then 8 when 4 then 9 end)
  where o.objid = old.fileid and old.storage in (3,4);
delete from oc_storages where numeric_id in (3,4);   -- DELETE 2
```

then `occ files:cleanup`: 106,384 orphaned file cache and 19 extended entries deleted. Favourites
kept (4 car folders in Pictures, the Pictures and Documents roots), 0 orphaned favourites, `status.php` ok.
Undo: stop Nextcloud and roll back `tank1tb/Apps` to that snapshot (affects all Docker volumes).

**Lesson:** decide the external storage paths before the first scan; changing them with `occ` means
re-indexing and this cleanup. To change one later, rename the storage row ("Renaming a share later").

## History

- AIO setup choices (user): Nextcloud Office **Collabora** (over Euro-Office), Fulltextsearch,
  Imaginary; Talk, ClamAV and Whiteboard off; Hub 26 Spring; timezone America/New_York.
- 2026-10-06: first external mounts used `NEXTCLOUD_MOUNT=/tank1tb` (Pictures, Documents). Media
  (`/media`) and Other (`/other`) are outside `/tank1tb`, so the mount moved to `/srv/nas` with bind
  mounts, the two mounts were repointed and Music, Media, Other added.
- The old `nextcloud/compose.yaml` (from the previous install) pointed at `/tank/Nextcloud` and had
  custom DNS servers; replaced. Container DNS works with Docker's defaults.
