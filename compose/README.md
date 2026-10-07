# Compose projects

One folder per app. Docker itself is set up in `docs/services/docker.md` (Checkpoint 5).

```text
compose/<app>/compose.yaml     # in git
compose/<app>/.env.example     # in git, placeholder values only
compose/<app>/.env             # NOT in git (gitignored): real passwords, tokens
/tank1tb/Apps/<app>/           # the app's config/database (snapshotted + copied nightly)
/media/...                     # big disposable files the app reads (movies, TV)
```

## Adding an app

1. `mkdir compose/<app>` and write `compose.yaml` (template below).
2. `sudo mkdir /tank1tb/Apps/<app> && sudo chown ghost:nas /tank1tb/Apps/<app>`
   (some images want their own uid; the app's doc says which).
3. Secrets go in `.env`; commit only `.env.example`.
4. `cd compose/<app> && docker compose up -d`, then `docker compose logs -f`.
5. Test it, then add a row to the table below and a doc under `docs/services/`.

```yaml
services:
  <app>:
    image: <publisher>/<app>:<pinned-version>   # pin a version; upgrade on purpose
    container_name: <app>
    restart: unless-stopped                     # comes back after reboot
    env_file: .env                              # only if it has secrets
    volumes:
      - /tank1tb/Apps/<app>:/config
    ports:
      - "8096:8096"                             # LAN-wide; use 127.0.0.1:8096:8096 for local-only
```

## Apps

| App | Folder | Data | Ports | Checkpoint | Status |
|---|---|---|---|---|---|
| Jellyfin | `compose/jellyfin/` | `/tank1tb/Apps/jellyfin` | 8096 | 7 | planned |
| Nextcloud AIO | `nextcloud/` | `/tank1tb/Nextcloud` + volumes in `/tank1tb/Apps/docker-volumes` | 8080 (LAN), 11000 (local, Funnel) | 8 | running 2026-10-06 |
