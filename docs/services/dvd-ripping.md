# DVD ripping: disc → NAS → LG TV

**Written:** 2026-10-04. **Status: plan, not yet tested.** Nothing below is installed except
the drive's fstab entry. Update this file with the real commands once the first disc is done.

## Goal

Put a movie DVD in MOTHERLODE's drive, rip it to a file, store it in the NAS movie library,
and watch it on the LG TV over the home network. The disc is only needed once.

```text
DVD in MOTHERLODE's drive (/dev/sr0)
  → rip and encode on MOTHERLODE (HandBrake)
  → /media/Movies/<Title> (Year)/<Title> (Year).mkv    (ZFS media pool)
  → Jellyfin on MOTHERLODE (Checkpoint 7) scans the library
  → Jellyfin app on the LG webOS TV plays it over the LAN
```

The drive is inside MOTHERLODE, so ripping happens there directly. There is no need to copy
the file to the Windows PC first. The PC (browser at `http://192.168.1.59:8096`) and the phone
(over Tailscale) can play the same library through Jellyfin.

Rip only discs you own. Borrowed discs (for example from a public library) should not end up as
permanent copies on the NAS.

## The drive

| Item | Value |
|---|---|
| Model | ASUS DRW-24B1ST (SATA DVD±RW burner) |
| Device | `/dev/sr0` (symlink `/dev/cdrom`); `ghost` is in the `cdrom` group |
| Reads | CD, DVD, DVD±R DL. **No Blu-ray.** |
| fstab | `/dev/sr0  /mnt/cdrom  udf,iso9660  user,noauto  0 0` |

### Why `/mnt/cdrom` and not `/media/cdrom0`

`/media` is the mountpoint of the ZFS `media` pool. Debian's installer put the drive at
`/media/cdrom0`, inside the pool's directory. During Checkpoint 2 (2026-10-04) that line was
commented out so the pool could mount on an empty `/media`. It was then restored with the
mount point moved to `/mnt/cdrom`, outside ZFS. Because the drive is in fstab, udisks (the XFCE
desktop automounter) also uses `/mnt/cdrom` instead of creating a directory under `/media`.

Ripping reads the raw device `/dev/sr0`, so the disc does **not** need to be mounted. The fstab
entry only matters for browsing a data CD/DVD (`mount /mnt/cdrom`, no sudo needed because of `user`).

## Tools (planned)

**HandBrake (`handbrake-cli`, Debian main) + `libdvd-pkg` (Debian contrib).** Commercial DVDs are
CSS-encrypted, and `libdvd-pkg` downloads and builds `libdvdcss` so HandBrake can read them.
HandBrake re-encodes the DVD's MPEG-2 video to H.264, which:

- every Jellyfin client direct-plays, the LG TV included, with no transcoding load on the server;
- is about 1–2 GB per movie instead of 4–8 GB;
- deinterlaces the 480i DVD video once, at rip time.

Alternative: **MakeMKV** makes a lossless copy (original MPEG-2, all audio tracks and
subtitles) in one step. It is not in Debian (build from makemkv.com, free beta key). Use it if
an exact archive matters more than file size. Jellyfin may transcode its MPEG-2 for some clients,
which the i7-6700 handles easily at DVD resolution.

## Planned procedure

One-time setup:

```bash
sudo apt install handbrake-cli libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg          # downloads and builds libdvdcss
HandBrakeCLI --preset-list 2>&1 | grep -i 'mkv'   # confirm the preset name used below
```

Writing to `/media/Movies` needs the `nas` group (Checkpoint 4; the directory is
`root:1001 2775`). Until then, run the rip with `sudo`, then `sudo chown -R ghost:1001` the new folder.

Per disc:

```bash
HandBrakeCLI -i /dev/sr0 -t 0 --scan 2>&1 | grep -E '^\s*\+ title|duration'   # find the main title
T="Movie Title (Year)"
mkdir -p "/media/Movies/$T"
HandBrakeCLI -i /dev/sr0 --main-feature \
  --preset "H.264 MKV 480p30" \
  --all-audio --all-subtitles \
  -o "/media/Movies/$T/$T.mkv"
eject /dev/sr0
```

`--main-feature` picks the longest title. Some discs have decoy titles. If the result is
wrong, use the scan output and `-t <n>` instead.

Naming: `Movies/<Title> (Year)/<Title> (Year).mkv`, the layout Jellyfin expects (Checkpoint 7).

## Watching on the TV

Depends on Checkpoint 7 (Jellyfin):

1. Jellyfin library "Movies" → `/media/Movies` (mounted read-only into the container).
2. On the LG TV: install **Jellyfin** from the LG Content Store and point it at
   `http://192.168.1.59:8096`.
3. After a rip, Jellyfin picks the file up on its next library scan (or *Scan All Libraries*).
4. Check *Playback Info* in Jellyfin: it should say **Direct Play**.

## Where the files live and what protects them

`/media` is the single-disk `media` pool on the Seagate 2 TB, which is **disposable by design**:
no mirror, no snapshots, no replication. If the disk dies, the movies are re-ripped from the
discs. Keep the discs. 1.8 TB holds roughly 900–1,500 H.264 DVD rips.

## Open items

- [ ] Install HandBrake + libdvd-pkg, rip one disc, record the exact commands, preset and file size here.
- [ ] Confirm Direct Play on the LG TV (Checkpoint 7).
- [ ] Decide whether to keep a lossless MakeMKV copy for a few favourites.
