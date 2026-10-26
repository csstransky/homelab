# Jellyfin (Checkpoint 7)

**Running since:** 2026-10-25. Wizard done and LG TV direct-play verified 2026-10-26.

## What is running

| Item | Value |
|---|---|
| Compose | `compose/jellyfin/compose.yaml` |
| Image | `jellyfin/jellyfin:12.3.20261023-013714` (Jellyfin 12.3.0), pinned |
| Runs as | `1000:1001` (ghost:nas), so it can read the `nas` media folders |
| Network | host: web/app on **8096**, client discovery on **7359/udp** |
| LAN address | `http://192.168.1.59:8096` (also `http://MOTHERLODE:8096`) |
| Remote | `http://100.111.72.91:8096` or `http://motherlode.tailb6c0f2.ts.net:8096` with Tailscale on. **Not** on the Funnel. |
| Config / cache | `/tank1tb/Apps/jellyfin/{config,cache}` (snapshotted, copied nightly) |
| Media (read-only) | `/media/Movies`, `/media/TV`, `/media/Music` |
| Transcoding | CPU only. No `nvidia-container-toolkit` yet (see below) |

## Folder layout

```text
/media/Movies/<Title> (Year)/<Title> (Year).mkv
/media/TV/<Show>/Season 01/<Show> S01E01.mkv
```

Copy files in over Samba (`\\MOTHERLODE\Media`). Ripping: `docs/services/movie-ripping.md`.
Test file: `/media/Movies/Big Buck Bunny (2008)/` (Blender Foundation, CC BY 3.0, 1080p H.264).

## First-time setup (user)

1. Browser: `http://192.168.1.59:8096`. Wizard: language, admin user + password (not in git).
2. Libraries: Movies → `/media/Movies`, Shows → `/media/TV` (Music → `/media/Music` optional).
3. Leave "Allow remote connections" on (it only means the tailnet here; nothing is port-forwarded).
4. LG TV: Content Store → install **Jellyfin** → it should find MOTHERLODE, or enter `http://192.168.1.59:8096`.
5. Play Big Buck Bunny. Dashboard → Activity should say **Direct Play**, not Transcode.

## Watching away from home

Tailscale on the device, then the Jellyfin app with server `http://motherlode.tailb6c0f2.ts.net:8096`.
Works on phones, tablets, laptops and Android/Google TV sticks (they run Tailscale); a hotel TV
cannot. Jellyfin is **not** on the Funnel and must not be (rule in `AGENTS.md`). Remote quality is
capped by the home upload speed: set Dashboard → Playback → "Internet streaming bitrate limit"
below it, and Jellyfin transcodes down to fit (which is where the GPU helps).

## Transcoding decision

The LG TV direct-plays H.264/H.265 in MP4/MKV, so most files need no transcoding. If a real file
shows "Transcode" and stutters, add NVENC on the GTX 1050 Ti: install `nvidia-container-toolkit`
(container side only; does **not** touch `nvidia-kernel-dkms`, see `docs/recovery/NVIDIA-DRIVER-INCIDENT.md`)
and give the container the GPU. The HD 530 iGPU is off while the card is in, so Quick Sync is not an option.

## Everyday commands

```bash
cd ~/homelab/compose/jellyfin
docker compose ps
docker compose logs -f
curl -s http://127.0.0.1:8096/health          # "Healthy"
```

## Verification (2026-10-25)

| Check | Result |
|---|---|
| Container | `Up (healthy)`, `restart: unless-stopped` |
| `/health` on 127.0.0.1 | `Healthy` |
| `/health` on the tailnet IP | HTTP 200 |
| Discovery port | 7359/udp listening |
| LG TV, Jellyfin app, Big Buck Bunny (2026-10-26) | plays; Direct Play (no ffmpeg transcode log) |
| Startup log | only EF Core "rebuild pending" migration warnings on the fresh database; no errors |
