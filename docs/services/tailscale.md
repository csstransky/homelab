# Tailscale (Checkpoint 6)

**Installed and tested from outside the LAN:** 2026-10-04.

Tailscale is a private network made of your own devices (the "tailnet"). Each device gets a
`100.x` address and a name; traffic between them is end-to-end encrypted (WireGuard). Nothing is
port-forwarded on the router, so nothing on MOTHERLODE is exposed to the public internet.

## What is set up

| Item | Value |
|---|---|
| Source | Tailscale's official repo, `/etc/apt/sources.list.d/tailscale.list` (trixie) |
| Repo key | `/usr/share/keyrings/tailscale-archive-keyring.gpg`, fingerprint `2596 A99E AAB3 3821 893C 0A79 458C A832 957F 5868` |
| Version | 1.102.4, `tailscaled.service` enabled |
| Command | `sudo tailscale up --ssh --operator=ghost --hostname=motherlode` |
| Tailnet | `csstransky@github`, MagicDNS suffix `tailb6c0f2.ts.net` |
| MOTHERLODE | `motherlode.tailb6c0f2.ts.net` (short: `motherlode`), `100.111.72.91`, `fd7a:115c:a1e0::ea37:485c` |
| Phone | `oneplus-13`, `100.78.106.52` (Android: Tailscale, Termius, CX File Explorer) |
| Tailscale SSH | on (`--ssh`): port 22 on the tailnet address is answered by `tailscaled`, authorised by the tailnet policy, not by OpenSSH keys/passwords |
| Operator | `ghost` can run `tailscale` commands without sudo |
| MagicDNS on this host | on: `/etc/resolv.conf` is written by Tailscale (`nameserver 100.100.100.100`); normal names and `motherlode.local` still resolve |
| Subnet routes / exit node | none. Home Assistant and the UDM are **not** reachable through MOTHERLODE |
| Connectivity | direct UDP (no relay needed): `tailscale netcheck` UDP: true |
| Node key expiry | disabled (2026-10-06) |

On the LAN, OpenSSH (`ssh ghost@192.168.1.59`) and Samba keep working exactly as before.

## Using it

| From | What | Address |
|---|---|---|
| Phone (Termius) | SSH | `ghost@motherlode` |
| Phone (CX File Explorer) | Files (SMB) | `motherlode.tailb6c0f2.ts.net`, user `ghost`, Samba password |
| Windows away from home | Files | `\\motherlode.tailb6c0f2.ts.net\Documents` (Tailscale app running) |
| Any tailnet device | SSH | `ssh ghost@motherlode` |

```bash
tailscale status                 # devices and connection state
tailscale ip                     # this machine's tailnet addresses
tailscale ping oneplus-13        # direct vs relayed path
sudo journalctl -u tailscaled | grep 'SSH login'   # Tailscale SSH audit log
```

## Verification (2026-10-04)

| Check | Result |
|---|---|
| Login | `Success.`; same MagicDNS name as before the reinstall |
| Phone on 5G (Wi-Fi off), Tailscale app | both devices connected (screenshot) |
| SSH from phone (Termius) | `audit: SSH login: user=ghost ... from=100.78.106.52 ts_user=csstransky@github node=oneplus-13` at 22:31; ran `ls`, wrote `~/word.txt` |
| SMB from phone (CX File Explorer) | browsed `Photos` (41 GB shown); uploaded 3 screenshots to `Other` at 22:38–22:39, landed as `ghost:nas` in `/other` |
| Host after install | DNS (public and `.local`) works; Samba, Docker, timers active; LAN address unchanged |

## To do (admin console, https://login.tailscale.com/admin/machines)

- ~~Disable key expiry on motherlode~~ done by the user 2026-10-06 (`KeyExpiry` absent).
- Remove stale machines from before the reinstall, if any are listed.

## Decisions

- **Tailscale SSH on:** login is tied to the Tailscale account (GitHub), audited in the journal,
  no SSH keys to copy to the phone. The default tailnet policy may ask for a browser re-check.
- **No subnet routing:** off until there is a reason to reach Home Assistant / the UDM remotely
  through MOTHERLODE (`tailscale set --advertise-routes=192.168.1.0/24` + approve in console).
- **Funnel on for Nextcloud only (2026-10-06, user choice: public share links):**
  `tailscale funnel --bg 11000` → `https://motherlode.tailb6c0f2.ts.net` (port 443) is on the public
  internet. Approved in the admin console (Funnel + HTTPS certificates). Off: `tailscale funnel --https=443 off`.
  Funnel only allows ports 443/8443/10000; SSH, Samba and the AIO interface stay tailnet/LAN-only.
- Auth keys are never committed. The login was interactive; no key exists.

## Rebuild

```bash
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update && sudo apt-get install tailscale
sudo tailscale up --ssh --operator=ghost --hostname=motherlode   # open the printed link, log in with GitHub
```
Delete the old `motherlode` in the admin console first, or the new one becomes `motherlode-1`.
