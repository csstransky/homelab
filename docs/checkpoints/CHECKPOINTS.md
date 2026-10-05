# MOTHERLODE — Build Checkpoints

**Created:** 2026-09-28
**Purpose:** The single ordered to-do list for turning the fresh Debian 13 install into
the finished NAS. Work proceeds one checkpoint at a time. A checkpoint is DONE only when
every item in its "Done when" list has been verified with a command and the linked
documentation has been committed.

Update the status table below as checkpoints close. Do not skip ahead.

---

## 0. Source-of-truth reconciliation

Three planning documents exist. Later documents override earlier ones where they conflict.

| Date | Document | Status |
|---|---|---|
| 2026-09-14 | `MOTHERLODE_Homelab_Build_Plan(3).txt` | Overall roadmap (phases 1–12). Still the goal list. Its storage naming (`tank/...`) is **superseded**. |
| 2026-09-14 | `MOTHERLODE_HDD_Health_Report(4).txt` | Drive SMART baseline. Still valid as history; drive roles were finalized later. |
| 2026-09-27 | `MOTHERLODE NAS — Complete Rebuild Progress Report & AI Handoff.md` | **Authoritative storage architecture** (three pools + `/other`) and Samba design. Its "COMPLETE" claims about installed software are **no longer true**: the OS was reinstalled afterwards. |
| 2026-09-28 | This repository (`AGENTS.md`, `docs/recovery/NVIDIA-DRIVER-INCIDENT.md`, `ai/`) | Current OS, GPU driver and AI setup. |

### Decisions carried forward (do not redesign)

- Pools: `tank1tb` (mirror, primary important data), `tank500gb` (mirror, backup target),
  `media` (single disk, disposable), plus ext4 `/other` (label `other`).
- Datasets on `tank1tb`: `Documents`, `Photos`, `Music`, `Backups`, `Nextcloud`, `Apps`.
  No `data/` wrapper dataset.
- `/media/Movies`, `/media/TV`, `/media/Music` are plain directories on the `media` pool.
- `/tank1tb/Music` is the important music library. `/media/Music` is disposable.
- `/tank1tb/Nextcloud` is **not** a Samba share.
- Samba: `security = user`, no guest, SMB2 minimum, `nas` group with setgid 2775 dirs,
  shares `Documents`, `Photos`, `Music`, `Media`, `Other`, user `ghost`.
- Seagate ST2000DX002 (2 TB) holds only disposable media. Never important data.
- Secure Boot stays **disabled** (ZFS module signing).
- NVIDIA: proprietary `nvidia-kernel-dkms` only. Never the open module.
- Always `/dev/disk/by-id/`, never `/dev/sdX`, in anything persistent.
- Home Assistant stays on the Raspberry Pi. The NAS serves it; it does not host it.
- Tailscale MagicDNS for remote access. No DuckDNS cron.

### Verified system state — 2026-09-28

| Item | State |
|---|---|
| OS | Debian 13 (trixie), kernel 6.12.107+deb13-amd64, hostname `MOTHERLODE` |
| LAN | `eno1` 192.168.1.59/24, UniFi fixed-IP reservation set 2026-09-28 (was .124 on 09-14, .64 historically) |
| Secure Boot | disabled |
| GPU | GTX 1050 Ti, driver 550.163.01, `nvidia-kernel-dkms` — working. **2026-10-04: card removed, hardware untested; display on Intel HD 530, Ollama CPU-only** (`docs/hardware/GPU.md`) |
| Ollama | installed and running (`ollama.service`) |
| SSH | `ssh.service` running |
| Time | America/New_York, NTP synchronized |
| ZFS software | **not installed** (`zfsutils-linux`, `zfs-dkms` absent). 2026-10-04: 2.3.9 installed, pools imported (Checkpoint 2) |
| ZFS on disk | pool labels present and intact: `tank1tb`, `tank500gb`, `media` |
| `/other` | ext4 partition present (UUID `5250af8d-6988-4201-9c8c-bedd00c234b1`), **not in fstab, not mounted**. 2026-10-04: in fstab and mounted |
| Samba | **not installed**; `nas` group does not exist; `ghost` not in `nas`. 2026-10-04: installed, `nas` GID 1001 (Checkpoint 4) |
| Docker | **not installed**; `ghost` not in `docker` |
| Tailscale | **not installed** |
| Sleep | disabled 2026-09-29: sleep/suspend/hibernate targets masked, XFCE idle sleep off (`docs/services/always-on.md`) |
| apt sources | main, contrib, non-free, non-free-firmware enabled (contrib needed for ZFS) |
| sudo | `ghost` NOPASSWD via `/etc/sudoers.d/ghost-nopasswd` (2026-09-28; user chose to keep it) |

Current drive letters (they WILL change between boots; by-id is authoritative):

| by-id | Today | Role |
|---|---|---|
| `ata-Crucial_CT250MX200SSD1_154511053F30` | sda | Debian OS. **Never touch.** |
| `ata-ST2000DX002-2DV164_Z4ZB3346` | sdb | `media` (single) |
| `ata-WDC_WD6400AAKS-00A7B2_WD-WCASYD471432` | sdc | part1 `tank500gb` mirror, part2 ext4 `other` |
| `ata-ST500DM002-1BD142_W2AF3DHD` | sdd | `tank500gb` mirror |
| `ata-TOSHIBA_DT01ACA100_Z5B2VRDNS` | sde | `tank1tb` mirror |
| `ata-WDC_WD10EZEX-60M2NA0_WD-WCC3F2CYKRSN` | sdf | `tank1tb` mirror |

---

## Status

| # | Checkpoint | Status | Closed | Docs |
|---|---|---|---|---|
| 0 | Source-of-truth reconciliation + this file | ✅ done | 2026-09-28 | this file |
| 1 | Debian foundation | ✅ done (Windows SSH test pending) | 2026-09-28 | `docs/hardware/MOTHERLODE.md`, `docs/architecture/network.md` |
| 2 | ZFS: install + import existing pools + `/other` | 🟨 imported, reboot check pending | | `zfs/README.md` |
| 3 | Storage protection: SMART, scrubs, snapshots, replication | ⬜ deferred by user until after Samba; still due before real data | | `zfs/SNAPSHOTS.md`, `scripts/maintenance/` |
| 4 | Samba (Windows LAN access) | ✅ done | 2026-10-04 | `samba/` |
| 5 | Docker foundation | ⬜ | | `docs/services/docker.md` |
| 6 | Tailscale (remote access) | ⬜ | | `docs/services/tailscale.md` |
| 7 | Jellyfin (movies on the LG TV) | ⬜ | | `compose/jellyfin/` |
| 8 | Nextcloud AIO on `/tank1tb/Nextcloud` | ⬜ | | `nextcloud/` |
| 9 | Music: NAS library → Music Assistant / Sonos, YouTube audio | ⬜ | | `docs/services/music.md` |
| 10 | Reboot / autostart / recovery validation | ⬜ | | `docs/recovery/BOOT-RECOVERY.md` |
| 11 | Backups off the NAS + restore test | ⬜ | | `docs/recovery/BACKUP-RESTORE.md` |
| 12 | AdGuard Home DNS filtering | ⬜ | | `compose/adguard/` |
| 13 | Monitoring + alerts | ⬜ | | `docs/services/monitoring.md` |
| 14 | Ubiquiti VLAN segmentation (optional) | ⬜ | | `docs/architecture/network.md` |

Checkpoints 1–9 deliver the stated goals: Windows access on the LAN, remote access,
movies on the TV, and music to Home Assistant / Music Assistant. 10–14 make it trustworthy.

---

## Checkpoint 1 — Debian foundation

Build Plan phase 1.

Steps:
1. `apt update && apt full-upgrade && apt autoremove`, then reboot if a kernel changed.
   Confirm the NVIDIA module still loads after any kernel update (`nvidia-smi`).
2. Install base admin tools: `curl wget git vim htop btop unzip ca-certificates gnupg lsb-release smartmontools`.
3. Confirm `ssh.service` enabled; test `ssh ghost@192.168.1.59` from the Windows machine.
4. **User action:** create a Ubiquiti DHCP reservation for MOTHERLODE's `eno1` MAC `18:60:24:ad:92:ac`.
   Record the chosen address here and in `docs/architecture/network.md`.
5. Decide sudo policy for the build (password prompts vs. a NOPASSWD drop-in for `ghost`).
6. ~~Record hardware inventory~~ — done 2026-09-28: `docs/hardware/MOTHERLODE.md` (add `dmidecode` detail when root is available).

Done when:
- [x] `apt full-upgrade` reports nothing to do; `nvidia-smi` works. (No kernel change on 2026-09-28, so no reboot was required.)
- [ ] SSH login from the Windows machine succeeds (user to confirm: `ssh ghost@192.168.1.59`).
- [x] UniFi fixed-IP reservation 192.168.1.59 on `18:60:24:ad:92:ac`; will be confirmed across the Checkpoint 2 reboot.
- [x] `docs/hardware/MOTHERLODE.md` committed.

Notes 2026-09-28: duplicate installer source `/etc/apt/sources.list.d/contrib.list` disabled
(main `sources.list` already has contrib/non-free/non-free-firmware). Base tools installed
including `smartmontools` (`smartctl` is in `/usr/sbin`, use `sudo`).
The machine hard-froze during the commit of this checkpoint; see
`docs/recovery/2026-09-28-HARD-FREEZE.md`. Run memtest86+ before trusting the box overnight.

## Checkpoint 2 — ZFS: install and import the existing pools

Rebuild Report sections 5–18. **Import, do not create.**

Steps:
1. `apt install zfs-dkms zfsutils-linux` (contrib). Confirm `modprobe zfs` works with Secure Boot off.
2. `zpool import` (scan only) — expect `tank1tb`, `tank500gb`, `media` to be listed, all ONLINE.
3. `zpool import -d /dev/disk/by-id -o cachefile=/etc/zfs/zpool.cache <pool>` for each pool.
   If a pool was not exported cleanly it may need `-f`; confirm the hostid situation first.
4. Verify `zfs list`, mountpoints (`/tank1tb/*`, `/tank500gb`, `/media`), `zpool status` clean.
5. Check the `/media` mountpoint collision with Debian's `/media/cdrom0` fstab line; remove
   the cdrom line or confirm the pool mounts over it cleanly.
6. Add `/other` to fstab by UUID (`defaults,noatime 0 2`), `systemctl daemon-reload`, mount.
7. Enable `zfs-import-cache`, `zfs-mount`, `zfs.target`. Reboot. Confirm everything is back.
8. Write `zfs/README.md`: pools, by-id members, datasets, properties, import procedure.

Done when:
- [ ] All three pools ONLINE with zero errors after a reboot, mounted where expected.
- [ ] `/other` mounted from fstab after reboot.
- [x] `zfs/README.md` committed with the exact by-id → pool mapping.

Notes 2026-10-04:
- Step 1 was done on 2026-09-28 (the DKMS build was running during the hard freeze, and
  `dpkg --configure -a` finished it). `zfs` 2.3.9 loads.
- Before importing, `kernel.hung_task_panic` went back to 0 in
  `/etc/sysctl.d/90-lockup-panic.conf`, so slow I/O from the Toshiba or a scrub cannot panic the NAS.
- All three pools needed `-f`: they were *last accessed by another system*, which is the old
  install's hostid. Imported by-id into `/etc/zfs/zpool.cache`, all ONLINE. The first scrubs
  of all three found 0 errors, but the pools are nearly empty.
- The `/dev/sr0 /media/cdrom0` fstab line was moved, not dropped: the DVD drive is now at `/mnt/cdrom`, outside
  the ZFS `media` pool. `/media/cdrom0` and `/media/cdrom` were removed. Movie ripping happens on the
  Windows PC's Blu-ray drive, not this drive (`docs/services/movie-ripping.md`).
- `/other` is in fstab by UUID and mounted. Its journal was replayed on the first mount.
- The ZFS boot units were already enabled by the package. Still to do: reboot and confirm that
  pools, `/other` and the .59 address all come back.
- The data directories are owned by `root:1001`, the old `nas` GID. Checkpoint 4 must use
  `groupadd -g 1001 nas`.

## Checkpoint 3 — Storage protection

Rebuild Report sections 49–52 (do this **before** any service writes real data).

Steps:
1. `smartd` enabled with short tests weekly and long tests monthly on all five HDDs; log to journal.
2. Run a fresh `smartctl -x` on every drive and update the drive health record in `docs/hardware/`.
3. Scrub schedule: monthly `tank1tb` and `tank500gb`; monthly `media` too (cheap early warning on the 2 TB).
   Debian ships `zfs-scrub-monthly@.timer` units; enable per pool.
4. Snapshots: install `sanoid`; policy per dataset. Suggested starting point:
   `Documents`, `Photos`, `Nextcloud`, `Apps`: hourly 24 / daily 30 / monthly 6.
   `Music`, `Backups`: daily 14 / monthly 3. `media`: no snapshots.
5. Replication: `syncoid` from `tank1tb/{Documents,Photos,Apps}` (and `Nextcloud` if it fits)
   to `tank500gb/`. Decide the exact set given `tank500gb` is ~464 G. Schedule nightly via systemd timer.
6. Commit sanitized sanoid config and timer units under `zfs/` and `systemd/`.

Done when:
- `smartctl -l selftest` shows a completed test scheduled by smartd.
- Scrub timers enabled and one manual scrub of each pool completes with 0 errors.
- Snapshots appear on schedule; a test file restored from a snapshot.
- A replicated dataset exists on `tank500gb` and a second syncoid run is incremental.

## Checkpoint 4 — Samba (Windows access on the LAN)

Rebuild Report sections 22–36. Recreate the documented configuration exactly.

Steps:
1. `apt install samba smbclient`.
2. `groupadd -g 1001 nas` (GID matches the existing directory ownership, see `zfs/README.md`); `usermod -aG nas ghost`.
3. Ownership `root:nas`, mode `2775` on `/tank1tb/{Documents,Photos,Music}`, `/media`,
   `/media/{Movies,TV,Music}`, `/other`.
4. Write `/etc/samba/smb.conf` from the Rebuild Report (shares: Documents, Photos, Music, Media, Other).
   Keep `/tank1tb/Nextcloud` out of Samba.
5. `smbpasswd -a ghost`; `testparm`; enable `smbd`. Decide whether `nmbd`/`wsdd2` is wanted for
   Windows network discovery.
6. Test from Windows: map `\\MOTHERLODE\Documents`, write, read, delete. Confirm the file lands as `ghost:nas`.
7. Commit `samba/smb.conf` (no secrets) and `samba/README.md`.

Done when:
- [x] Windows machine reads and writes all five shares by hostname or IP.
- [x] Written files show `ghost:nas` with group inheritance.
- [x] Config committed.

Notes 2026-10-04:
- Done out of order: the user chose Samba before Checkpoint 3. No real data until snapshots exist.
- `nas` created as GID 1001, so the existing `root:1001 2775` share roots needed no changes.
- `apt install --no-install-recommends samba smbclient attr wsdd2` (Samba 4.22.11). This skips the
  AD-DC/winbind recommends.
- `/etc/samba/smb.conf` = Rebuild Report section 26 verbatim (`samba/smb.conf`). `testparm` is clean
  (ROLE_STANDALONE). `smbd` listens on 139/445; `nmbd` is kept enabled; `wsdd2` was added for Windows discovery.
- Samba password set by the user (`pdbedit -L` → `ghost:1000:ghost`). An empty password is rejected
  (`NT_STATUS_LOGON_FAILURE`). Anonymous access is refused (`NT_STATUS_ACCESS_DENIED`). The Linux login
  password was not touched by `unix password sync` (`passwd -S`: last change 2026-09-28).
- smbclient write test, on localhost and `192.168.1.59`: put/get/mkdir on all five shares, data read back
  identical, files `ghost:nas 0664`, dirs `ghost:nas 2775`. Test files removed.
- Windows verified 2026-10-04: ZEPHYR (192.168.1.64) mapped all five shares (`smbstatus`: SMB3_11, signed)
  and wrote `hello.txt.txt` and `test2.txt` to Documents, both landing as `ghost:nas 664`. Server-side
  smbclient covered writes on the other four shares. The second Windows machine uses the same steps.
- Visual explainer: `samba/samba-explained.html`.

## Checkpoint 5 — Docker foundation

Build Plan phase 3.

Steps:
1. Docker Engine + Compose plugin from Docker's official Debian repository (trixie).
2. Decide `docker` group membership for `ghost` (root-equivalent trade-off) and record the decision.
3. Directory convention: compose projects in `~/homelab/compose/<service>/`, persistent app data in
   `/tank1tb/Apps/<service>/` (important) or `/media` (disposable). `.env` files are gitignored.
4. `hello-world` run; `docker compose version`.
5. Only install `nvidia-container-toolkit` if Checkpoint 7 shows transcoding is actually needed.

Done when:
- `docker compose` works as `ghost`; convention documented in `docs/services/docker.md`.

## Checkpoint 6 — Tailscale (remote access)

Build Plan phase 5; Rebuild Report section 40.

Steps:
1. Install Tailscale from the official repo; `tailscale up --ssh` (Tailscale SSH) with `ghost` as operator.
2. Confirm MagicDNS name (previously `motherlode.tailb6c0f2.ts.net`); record the current one.
3. From the phone off Wi-Fi: SSH to the MagicDNS name; open an SMB share if the client supports it.
4. Decide on subnet routing for reaching Home Assistant / UDM through MOTHERLODE. Off by default.
5. Document in `docs/services/tailscale.md`. Never commit auth keys.

Done when:
- Remote SSH over Tailscale works from outside the LAN.
- MagicDNS hostname recorded; nothing exposed to the public internet.

## Checkpoint 7 — Jellyfin (movies on the LG TV)

Build Plan phase 7.

Steps:
1. `compose/jellyfin/compose.yaml`: official image, config in `/tank1tb/Apps/jellyfin`,
   `/media/Movies`, `/media/TV`, `/media/Music` mounted read-only, host networking or port 8096.
2. Library structure: `Movies/<Title> (Year)/<file>`, `TV/<Show>/Season 01/<file>`.
   Movies are ripped on the Windows PC (Blu-ray, MakeMKV) and copied to `\\MOTHERLODE\Media\Movies`
   (`docs/services/movie-ripping.md`).
3. Install the Jellyfin app on the LG webOS TV; connect over the LAN; play a file. Prefer Direct Play.
4. If transcoding is needed, add NVENC via `nvidia-container-toolkit` (proprietary driver is fine for this).
   While the GTX 1050 Ti is out, the option is Intel Quick Sync on the HD 530 (`/dev/dri`).
5. Remote playback test over Tailscale from the phone.

Done when:
- A movie plays on the TV from `/media/Movies` without transcoding.
- Compose file committed; Jellyfin restarts on reboot.

## Checkpoint 8 — Nextcloud AIO on `/tank1tb/Nextcloud`

Build Plan phase 6; Rebuild Report sections 37–39; existing `nextcloud/compose.yaml`.

Steps:
1. Update `nextcloud/compose.yaml`: `NEXTCLOUD_DATADIR=/tank1tb/Nextcloud`, volume path likewise.
   Keep `APACHE_IP_BINDING=127.0.0.1`, `APACHE_PORT=11000`.
2. Decide the front door: Tailscale Serve / Funnel to port 11000, or a reverse proxy. Prefer Tailscale-only first.
3. Deploy; complete AIO setup using the Tailscale hostname as the domain.
4. Test upload/download in the browser from the LAN and remotely.
5. Confirm `/tank1tb/Nextcloud` is snapshotted (Checkpoint 3) and still not a Samba share.

Done when:
- Nextcloud reachable remotely over Tailscale, files landing under `/tank1tb/Nextcloud`.
- Compose committed without secrets.

## Checkpoint 9 — Music to Home Assistant / Music Assistant

Build Plan phase 8; Rebuild Report section 42.

Steps:
1. Music Assistant add-on on the Home Assistant Pi; add a filesystem (SMB) provider pointing at
   `\\MOTHERLODE\Music` (`/tank1tb/Music`). A dedicated read-only Samba user for MA is preferable to reusing `ghost`.
2. Add the Sonos players in Music Assistant; test multi-room grouping.
3. YouTube: enable the YouTube Music provider in Music Assistant. Note that account cookies live on the Pi, not the NAS.
4. Arbitrary browser / phone audio: evaluate AirPlay or Chromecast targets via Music Assistant vs. the native Sonos app.
   Document what works and what does not.
5. Optionally expose `/media/Music` as a second MA provider.

Done when:
- Music from `/tank1tb/Music` plays on the Sonos speakers via Music Assistant.
- A YouTube source plays via Music Assistant.
- Phone-to-speaker path documented, including remote (Tailscale) behaviour.

## Checkpoint 10 — Reboot, autostart and recovery validation

Steps:
1. Cold reboot. Verify in order: ZFS pools, `/other`, Samba, Docker containers, Tailscale, Jellyfin, Nextcloud.
2. Write `docs/recovery/BOOT-RECOVERY.md` (referenced by `AGENTS.md` but missing): how to import pools
   manually, what to do if a mirror member is missing, how to reach the machine if networking fails.
3. Note the known hardware quirks (long POST, HECI message, sleep/wake) and disable suspend on the server.

## Checkpoint 11 — Backups outside the NAS

Build Plan phase 11.

Steps:
1. Define irreplaceable data: `Documents`, `Photos`, Nextcloud data, service configs.
2. Choose an independent target (external USB disk rotated off-site, or a cloud bucket via `restic`/`rclone`).
3. Automate; encrypt; test a restore of a real file.
4. Document in `docs/recovery/BACKUP-RESTORE.md`.

## Checkpoint 12 — AdGuard Home

Build Plan phase 9. Static LAN address via Ubiquiti reservation; DHCP advertises AdGuard as DNS;
conservative blocklists; verify a client resolves through it.

## Checkpoint 13 — Monitoring and alerts

smartd and ZFS event (`zed`) email/notification, disk-space alerts, a basic dashboard only if it earns its keep.

## Checkpoint 14 — Ubiquiti VLANs (optional)

Build Plan phase 10. Server / trusted / IoT segmentation, TV restricted to Jellyfin and Home Assistant.
