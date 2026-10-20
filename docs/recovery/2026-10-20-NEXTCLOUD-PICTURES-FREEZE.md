# 2026-10-20: Nextcloud freezes opening Pictures; the Kia favourite will not open

**Short version:** nothing in the setup was broken. Pictures has **1,424 items loose in its top
folder**, and only **821 of ~18,000** photos, videos and PDFs had a thumbnail. Opening Pictures made
the server render hundreds of thumbnails on the spot, on 8 GB of RAM (slot test) already using swap.
Fix: `nextcloud-generate-missing-previews.timer` renders the missing ones every night.
Status: **probable cause, not yet proven** (the freeze itself was not reproduced; see Diagnosis 5).

## Symptoms

- In the web UI (https://motherlode.tailb6c0f2.ts.net), opening **Pictures** hangs and nothing loads.
- The **2016 Kia Forte** favourite (in Pictures) does not open.

## Diagnosis and evidence

1. **The server was healthy.** All 9 AIO containers `healthy`, `occ status` fine, 5 External Storage
   mounts present, the container sees `/srv/nas/*`. No server errors at the times the user browsed
   (phone Firefox, last active 15:54 UTC) besides the two warnings in point 4.
2. **The data was intact.** `2016 Kia Forte` is `Pictures/2016 Kia Forte` (29 items, ACL `user:www-data:rwx`),
   indexed in `oc_filecache` (storage 8). Favourites still set: the 4 car folders, WATCHES, ALICE,
   KEYBOARDS, KEYCAP_SETS, the Pictures and Documents roots.
3. **Pictures is big and mostly unrendered.**

   | | |
   |---|---|
   | Items in the top folder of Pictures | 1,424 (45 folders, ~1,380 files) |
   | Files in Pictures | ~13,400 (9,915 jpg, 2,215 png, 299 jpeg, 246 mp4 ...) , 42 GB |
   | Files with any preview (whole server) | **821** (1,651 previews, 246 MB) |
   | Photos/videos/PDFs without one | 17,885 (Pictures 12,437, Music 2,037, Documents 1,818, Other 1,101, admin 492) |

   The Files app asks for a 256×256 (grid) or 64×64 (list) preview of every visible file. A missing
   one is rendered right then: the full photo goes through Imaginary into a 2048 px "max" preview,
   then is scaled down. Measured: about **1 s per file** (`occ preview:generate`, of which 0.45 s is
   `occ` start-up). A screenful of new thumbnails is minutes of server work.
4. **Background scan never finished.** `nextcloud.log`, every cron run:
   `opendir(/srv/nas/Media/ghost): Permission denied` and `User admin still has unscanned files`.
   `/srv/nas/Media/ghost` is where XFCE mounts USB drives, deliberately left without `www-data`
   permissions (`docs/services/nextcloud.md`). Noise, not the freeze cause.
5. **Not reproduced.** Timing the real web requests needed a temporary Nextcloud app password, which
   the agent's permission system blocked. So the link from points 3 to the freeze is inferred, plus:
   - memory: `free` showed 7.7 GiB total, 1.9 GiB available, 1.4 GiB in swap; fulltextsearch 1.1 GiB.
   - the Kia folder is small (29 items), so it should open on its own. Likely its requests queued
     behind the Pictures thumbnail requests. **Test:** fresh tab, click the Kia favourite without
     opening Pictures first.

## Root cause (probable)

Nextcloud makes thumbnails only when someone views a file. Files added over Samba never get one
ahead of time, so the first visit to a large folder renders hundreds at once. 1,424 items in one
folder also hits known Nextcloud web UI slowness (forum threads below), and RAM is halved for the
slot test.

## Fix

`scripts/maintenance/nextcloud-generate-missing-previews.sh`, installed as
`/usr/local/sbin/nextcloud-generate-missing-previews`, run by a timer:

- Finds every image, video and PDF on the shares and in admin's files without a row in `oc_previews`.
- Runs `occ preview:generate -s 64x64 -s 256x256 -c <fileid>` on each (the first size also makes the
  large preview the photo viewer uses). Pictures first, newest first.
- Stops after 2.5 h (9,000 s) and continues the next night. ~18,000 files ≈ 3 nights.
- A file that fails is written to `/var/lib/nextcloud-generate-missing-previews/failed-fileids` and
  skipped later (delete that file to retry them).
- After the backlog, each night only renders what was added that day, in seconds.

It works with `nextcloud-fix-stale-previews` (every 15 min): that one deletes previews of files
replaced over Samba, this one renders them again overnight.

```bash
nextcloud-generate-missing-previews --dry-run   # count what is missing, per share (read-only)
nextcloud-generate-missing-previews 600         # run for 10 minutes now
journalctl -u nextcloud-generate-missing-previews.service   # what the nightly runs did
```

Install (done 2026-10-20):

```bash
sudo install -m 755 scripts/maintenance/nextcloud-generate-missing-previews.sh /usr/local/sbin/nextcloud-generate-missing-previews
sudo install -m 644 systemd/nextcloud-generate-missing-previews.service systemd/nextcloud-generate-missing-previews.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now nextcloud-generate-missing-previews.timer
```

The timer runs at **04:00**: after `ssd-backup` (02:30) and `syncoid-backup-tank1tb-to-tank500gb`
(03:00), done by 06:30. No `Persistent=`: a missed night is not caught up at boot, so a reboot during
the day does not start 2.5 h of rendering.

Why not the Preview Generator app: it is not installed, and its `preview:pre-generate` only sees
files written *through* Nextcloud, not Samba. The built-in `occ preview:generate` works per file.

### The `Media/ghost` warning (fixed 2026-10-20)

Hidden from Nextcloud like `lost+found` on Other. Nothing else on any share is named `ghost`
(checked `oc_filecache` and `find`). Side effect: nothing named `ghost` can be created through Nextcloud.
(The agent's first attempt was blocked by its permission system; run after the user asked for it.)

```bash
OCC='sudo docker exec --user www-data nextcloud-aio-nextcloud php occ'
$OCC config:system:set forbidden_filenames 2 --value=ghost   # index 0 .htaccess, 1 lost+found
$OCC files:scan --path="/admin/files/Media"                  # 4 folders, 1 updated, 1 removed, 0 errors
```

Afterwards the Media root's size went from -1 to 0 and no log entries appeared in the next cron run
(before: 2 warnings every 5 minutes).

### Considered: smaller previews (`preview_max_x/y` 2048 → 1024)

Would not save meaningful RAM: rendering decodes the whole original photo (a 12 MP photo is ~48 MB
in memory) whatever the output size. It saves disk (max previews average 291 KB here) and some
render time, at the cost of blurrier photos in the viewer on large screens. Not done.

## Verification

| Check | Result |
|---|---|
| 3 Kia photos, 1 Kia video by hand | `generated 2 previews` each, 0.9 to 1.1 s |
| `occ preview:generate` on a missing file | exit code 1, so failures are detected |
| `--dry-run` | 17,885 missing (table above), 0 known failures |
| 60 s test run | `Made previews for 55 files, 0 failed, in 60 s` |
| `Media/ghost` hidden | next cron run (18:40 UTC +5 min): 0 log entries; Media root size 0 (was -1) |
| Timer | enabled, next run Wed 2026-10-21 04:00; first full run started by hand 2026-10-20 14:29 |

## Preventing it

- Leave the timer on. A big batch of photos copied over Samba gets thumbnails the next night.
- Prefer subfolders over hundreds of loose files in one folder (the ~1,380 loose files in the top of
  Pictures). The browser-side slowness in large folders is a Nextcloud bug no server setting fixes.
- Do not use `occ preview:cleanup`: it deletes every preview and they all have to be made again.

## Others with the same problem

- [Nextcloud AIO freeze in browser](https://help.nextcloud.com/t/nextcloud-aio-freeze-in-browser/249886): AIO, opening photos in a 2,787-file folder freezes the browser 7 to 20 s; the viewer's work grows with the square of the folder size (client-side bug).
- [Nextcloud extremely slow in folder with 12000 small photos](https://help.nextcloud.com/t/nextcloud-extremely-slow-in-folder-with-12000-small-photos/188034): Docker + Imaginary, 8 GB RAM, 10 to 15 s even with previews made; Memories app shows the same folder in under 2 s.
- [Preview generation brings server to a halt (Docker)](https://help.nextcloud.com/t/preview-generation-brings-server-to-a-halt-extreme-cpu-and-ram-usage-docker/146065)
- [Nextcloud is not using pre-generated previews for external storage](https://help.nextcloud.com/t/nextcloud-is-not-using-pre-generated-previews-for-external-storage/83283)
- [Previews and high Imaginary requests](https://help.nextcloud.com/t/previews-and-high-imaginary-requests/162241)
- [Gallery too slow or hanging for large image collections](https://help.nextcloud.com/t/gallery-too-slow-or-hanging-for-large-image-collections/4420/21)
- [Occasionally very slow root directory PROPFIND](https://help.nextcloud.com/t/occasionally-very-slow-root-directory-propfind/130821)
