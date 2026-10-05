# Docker (Checkpoint 5)

**Installed and tested:** 2026-10-04.

## What is installed

| Item | Value |
|---|---|
| Source | Docker's official repo, `/etc/apt/sources.list.d/docker.sources` (suite `trixie`) |
| Repo key | `/etc/apt/keyrings/docker.asc`, fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` |
| Packages | `docker-ce` 29.8.2, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` (Compose v5.6.0) |
| Services | `docker.service`, `containerd.service`: enabled, start at boot |
| Images/containers | `/var/lib/docker` on the SSD (overlayfs, cgroup v2 / systemd) |
| Daemon config | `/etc/docker/daemon.json` (repo copy `docker/daemon.json`) |
| GPU | none: `nvidia-container-toolkit` is **not** installed (only if Checkpoint 7 needs NVENC) |

`daemon.json` sets the `local` log driver, 10 MB × 3 files per container, so container logs
cannot fill the SSD (the default `json-file` driver never rotates).

## Where things live

- **Compose files:** `~/homelab/compose/<app>/compose.yaml`, in git. Recipe in `compose/README.md`.
- **App data:** `/tank1tb/Apps/<app>/`, which gets snapshots and the nightly copy for free (Checkpoint 3).
  Large disposable data (movies) stays on `/media` and is mounted read-only where possible.
- **Images:** the SSD. They are re-downloadable, so they are not backed up.
- **Secrets:** `compose/<app>/.env`, gitignored. Commit `.env.example` with placeholders.

Checkpoint 5 is the foundation; each app checkpoint (7 Jellyfin, 8 Nextcloud, 9 Music, 12 AdGuard)
adds its own folder with this recipe.

## Decision: `ghost` is in the `docker` group

Being in the `docker` group is root-equivalent: anyone in it can start a container that mounts `/`.
`ghost` already has passwordless sudo, so this adds no new power; it just avoids typing `sudo` on
every `docker` command. Takes effect at the next login (or `newgrp docker` in a shell).

## Networking note

Ports published with `ports:` are reachable from the whole LAN (and, once Tailscale is up, the
tailnet). Docker writes its own nftables/iptables rules, so a host firewall such as `ufw` would
**not** block them. Publish as `127.0.0.1:PORT:PORT` for anything that should stay local. There is
no host firewall today; nothing is forwarded on the router, so nothing is on the public internet.

## Everyday commands

```bash
cd ~/homelab/compose/<app>
docker compose up -d            # start / apply changes
docker compose ps               # status
docker compose logs -f          # logs
docker compose pull && docker compose up -d   # upgrade (after bumping the pinned tag)
docker compose down             # stop and remove containers (data in /tank1tb/Apps stays)
docker system df                # disk used by images
docker image prune              # remove unused images
```

## Verification (2026-10-04)

| Check | Result |
|---|---|
| `docker run --rm hello-world` as `ghost` (no sudo) | "Hello from Docker!" |
| Compose project: `nginx:alpine` on `127.0.0.1:8099`, bind-mounting a folder in `/tank1tb/Apps` | `curl` returned the file from tank1tb; `compose down` removed container and network |
| `docker info` | overlayfs, cgroup v2, systemd cgroup driver, `local` logging |
| Other services after install | `smbd`, `nmbd`, `wsdd2`, `sanoid.timer`, `syncoid-tank500gb.timer` active; SSH and SMB still listening |

Test container, image and folder were removed afterwards. Containers coming back after a reboot is
checked with the first real app and again in Checkpoint 10.

## Install commands (for a rebuild)

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF2
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF2
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo cp ~/homelab/docker/daemon.json /etc/docker/daemon.json && sudo systemctl restart docker
sudo usermod -aG docker ghost
```
