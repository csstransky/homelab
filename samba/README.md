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

Set 2026-10-04 (a non-empty password; an empty one would let any LAN or tailnet device log in
as `ghost`). Set or change it (interactive; never stored in Git):

```bash
sudo smbpasswd -a ghost      # first time (adds the account)
sudo smbpasswd ghost         # change later
sudo pdbedit -L              # list Samba accounts
```

## Windows 10 / 11: all shares in File Explorer

Goal: every share shows up as a drive in File Explorer on both Windows machines, reconnects
at sign-in, and asks for the password only once.

**Quick look, no setup:** type `\\MOTHERLODE` in the Explorer address bar. All five shares are
listed. Sign in as `MOTHERLODE\ghost` and tick *Remember my credentials*.

**Permanent drive letters (recommended).** Open **Command Prompt** (not as administrator: a
mapping made in an elevated prompt does not show in Explorer) and paste:

```bat
cmdkey /add:MOTHERLODE /user:MOTHERLODE\ghost /pass
net use N: \\MOTHERLODE\Documents /persistent:yes
net use P: \\MOTHERLODE\Photos    /persistent:yes
net use M: \\MOTHERLODE\Music     /persistent:yes
net use V: \\MOTHERLODE\Media     /persistent:yes
net use O: \\MOTHERLODE\Other     /persistent:yes
```

`cmdkey ... /pass` prompts for the Samba password and stores it in Windows Credential Manager.
The `net use` lines then connect without asking. Drive letters: **N** Documents, **P** Photos,
**M** Music, **V** Media (video), **O** Other. Change any letter that is already taken on that PC.

Use the user name `MOTHERLODE\ghost`, not plain `ghost`, so Windows does not send its own PC
or Microsoft-account name as the domain.

How Windows finds the server by name: `wsdd2` answers WS-Discovery (so it appears under
*Network*) and LLMNR, and `nmbd` answers NetBIOS. If the name still does not resolve, use the IP:
`\\192.168.1.59\Documents` (and `cmdkey /add:192.168.1.59 ...`).

### Troubleshooting

| Symptom | Fix |
|---|---|
| *System error 1219: multiple connections ... by the same user, using more than one user name* | `net use * /delete /y`, then run the block again |
| Wrong password was saved | Control Panel → Credential Manager → Windows Credentials → remove `MOTHERLODE`, then `cmdkey` again |
| Drives show a red X after boot | Normal until opened. Clicking the drive reconnects. Check that MOTHERLODE is up. |
| `MOTHERLODE` not found, IP works | Name resolution only. Use the IP mapping, or check `systemctl status wsdd2 nmbd` |
| Windows 11 24H2 refuses the connection | 24H2 requires SMB signing. Samba 4.22 supports it, so check the password first (`smbclient //localhost/Documents -U ghost` on MOTHERLODE) |

When the machine is away from home, the same shares work over Tailscale (Checkpoint 6) at
`\\motherlode.<tailnet>.ts.net\Documents`.

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
