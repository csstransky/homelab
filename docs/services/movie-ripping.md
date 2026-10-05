# Movie discs: Blu-ray/DVD on the PC → NAS → LG TV

**Written:** 2026-10-04 (revised the same day: ripping happens on the Windows PC, not on MOTHERLODE).
**Status: plan, not yet tested.** Update with the real steps after the first disc.

## Goal

Put a movie disc in the **Blu-ray drive in the Windows PC**, rip it there, copy the file to
the NAS movie library over the home network, and watch it on the LG TV through Jellyfin.

```text
Blu-ray / DVD in the Windows PC's drive
  → rip on the PC (MakeMKV)
  → copy over SMB to \\MOTHERLODE\Media\Movies\<Title> (Year)\   (Samba, Checkpoint 4)
      = /media/Movies/... on MOTHERLODE (ZFS media pool)
  → Jellyfin on MOTHERLODE (Checkpoint 7) scans the library
  → Jellyfin app on the LG webOS TV plays it over the LAN
```

The PC and MOTHERLODE are on the same LAN (`192.168.1.0/24`), so the copy is a normal
Windows Explorer file copy into a mapped share.

Rip only discs you own. Borrowed discs (for example from a public library) should not end
up as permanent copies on the NAS.

## Ripping on the PC

**MakeMKV for Windows** (makemkv.com) reads both DVDs and Blu-rays, including their copy
protection, and writes a lossless `.mkv` with the original video, every audio track and the
subtitles. Pick the main title (usually the longest) and the audio/subtitle tracks you want.
Some discs have decoy titles. Check the length against the movie's runtime.

Approximate sizes: DVD 4–8 GB, Blu-ray 20–40 GB per movie. The 1.8 TB `media` pool holds
about 50–80 Blu-ray rips at full quality. If space gets tight, re-encode with
**HandBrake** on the PC (H.265 or H.264) to roughly 5–10 GB per Blu-ray.

Rip to the PC's local disk first, then copy to the NAS. Writing straight to the share over
the network works, but a local rip is faster and a failed rip doesn't leave half a file on the NAS.

## Copying to the NAS

1. In Explorer, map `\\MOTHERLODE\Media` (or `\\192.168.1.59\Media` if the name does not
   resolve). Sign in as `ghost` with the Samba password.
2. Create `Movies\<Title> (Year)\` and copy the file in as `<Title> (Year).mkv`.
3. On MOTHERLODE the file lands as `ghost:nas` mode `0664` under `/media/Movies/`.

Naming is what Jellyfin expects: `Movies/<Title> (Year)/<Title> (Year).mkv`. Extras can go in
an `extras/` subfolder next to the movie file.

## Watching on the TV

Depends on Checkpoint 7 (Jellyfin):

1. Jellyfin library "Movies" → `/media/Movies` (read-only in the container).
2. LG TV: install **Jellyfin** from the LG Content Store and point it at `http://192.168.1.59:8096`.
3. New rips appear after a library scan (*Scan All Libraries*, or the scheduled scan).
4. Check *Playback Info*: **Direct Play** is the goal. Blu-ray remuxes are high-bitrate H.264
   (sometimes VC-1) with lossless audio (TrueHD / DTS-HD). If the TV cannot decode the audio,
   Jellyfin transcodes the audio only, which is cheap. A video transcode of a 1080p remux is heavy
   for the i7-6700 alone. Intel Quick Sync on the HD 530 (or NVENC once the GTX 1050 Ti is back)
   is the fix if that happens.

The PC (browser at `http://192.168.1.59:8096`) and the phone (over Tailscale) play the same library.

## Where the files live and what protects them

`/media` is the single-disk `media` pool on the Seagate 2 TB, which is **disposable by design**:
no mirror, no snapshots, no replication. If the disk dies, the movies are re-ripped. Keep the discs.

## MOTHERLODE's own DVD drive

MOTHERLODE also has an ASUS DRW-24B1ST (DVD±RW, **no Blu-ray**) at `/dev/sr0`, mounted on
demand at `/mnt/cdrom` (`user,noauto` in fstab). It is not part of the movie workflow. It
stays available for data CDs/DVDs (`mount /mnt/cdrom`).

The mount point used to be `/media/cdrom0`, inside the ZFS `media` pool's mountpoint. It was
moved to `/mnt/cdrom` during Checkpoint 2 (2026-10-04) so nothing non-ZFS lives under `/media`.
Because the drive is in fstab, the XFCE automounter (udisks) also uses `/mnt/cdrom`.

## Open items

- [ ] Rip one Blu-ray with MakeMKV, copy it to `\\MOTHERLODE\Media\Movies`, record the file size and copy speed.
- [ ] Confirm Direct Play (video and audio) on the LG TV (Checkpoint 7).
- [ ] Decide on remux vs. re-encode once the space per movie is known.
