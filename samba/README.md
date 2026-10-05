# Samba on MOTHERLODE

**Set up:** 2026-10-04 (Checkpoint 4), recreating the design from the 2026-09-27 Rebuild
Report, sections 22–36. Config: `samba/smb.conf` (identical to `/etc/samba/smb.conf`).

## Shares

| Share | Path | Storage |
|---|---|---|
| `\\MOTHERLODE\Documents` | `/tank1tb/Documents` | ZFS mirror, important |
| `\\MOTHERLODE\Photos` | `/tank1tb/Photos` | ZFS mirror, important |
| `\\MOTHERLODE\Music` | `/tank1tb/Music` | ZFS mirror, the important music library |
| `\\MOTHERLODE\Media` | `/media` (`Movies`, `TV`, `Music`) | single disk, disposable |
| `\\MOTHERLODE\Other` | `/other` | ext4, misc |

`/tank1tb/Nextcloud` is **not** shared and must not be. Nextcloud owns that directory, and
files changed behind its back break its database.

## Security model

- `security = user`, `map to guest = Never`, `guest ok = no`: no anonymous access.
- `valid users = ghost` on every share. Samba has its own password database (`pdbedit -L`),
  separate from the Linux login password.
- `min protocol = SMB2`: SMB1 is off. `testparm` says *"SMB1 disabled -- no workgroup
  available"*. That is expected, not an error.
- No firewall on MOTHERLODE, and no port forwards on the UDM. SMB is reachable from the LAN,
  and from the tailnet once Tailscale is up (Checkpoint 6). Never forward 445 to the internet.

## Permissions

- Unix group `nas`, **GID 1001**. It was created with `groupadd -g 1001 nas` so it matches the
  ownership already stored on the ZFS datasets from the old install (no `chgrp -R` needed).
  `ghost` is a member.
- Share roots and media subfolders: `root:nas`, mode `2775`. The setgid bit makes new files
  inherit the `nas` group.
- `force group = nas`, `create mask = 0664`, `directory mask = 2775`: files written over SMB land
  as `ghost:nas 0664`, directories as `2775`.

## Packages and services

Installed with `--no-install-recommends` to skip the Active Directory domain-controller
packages (`samba-ad-dc`, `winbind`, `python3-samba`, ...), which a standalone server does not need:

```bash
sudo apt install --no-install-recommends samba smbclient attr wsdd2
```

| Service | Purpose |
|---|---|
| `smbd` | File sharing, TCP 445 (and 139) |
| `nmbd` | NetBIOS name service. Lets older lookups find `MOTHERLODE` by name. Kept enabled as in the old setup. |
| `wsdd2` | WS-Discovery + LLMNR. Makes MOTHERLODE show up under *Network* in Windows Explorer and resolve by name. |

Debian's default config is kept at `/etc/samba/smb.conf.debian-default`.

## Samba password

Set or change it (interactive; never stored in Git):

```bash
sudo smbpasswd -a ghost      # first time (adds the account)
sudo smbpasswd ghost         # change later
sudo pdbedit -L              # list Samba accounts
```

## Windows

```text
Explorer → This PC → Map network drive → \\MOTHERLODE\Documents
           (or \\192.168.1.59\Documents) → "Connect using different credentials" → ghost
```

Map each share you use. If Windows has cached a wrong login, clear it with `net use * /delete`
in a Windows terminal, or under *Credential Manager → Windows Credentials*.

## Adding folders vs. adding shares

A new **folder** inside an existing share needs no Samba change. Just create it.

A new **share** is for a new major storage category only: create the dataset/directory,
`root:nas 2775`, add a `[Name]` section modelled on the others, then:

```bash
sudo testparm -s && sudo systemctl reload smbd
```

and copy the new `/etc/samba/smb.conf` into `samba/smb.conf`.

## Checks

```bash
sudo testparm -s                       # config loads, ROLE_STANDALONE
systemctl is-active smbd nmbd wsdd2
sudo ss -tlnp | grep -E ':(139|445) '
smbclient -L localhost -U ghost        # lists the five shares + IPC$
```
