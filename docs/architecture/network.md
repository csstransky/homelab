# MOTHERLODE — Network

**Recorded:** 2026-09-28 (rewritten after the 2026-09-28 hard freeze destroyed the first version; see `docs/recovery/2026-09-28-HARD-FREEZE.md`).

## LAN

| Item | Value |
|---|---|
| Interface | `eno1` — Intel I219-LM (`8086:15b7`) |
| MAC | `18:60:24:ad:92:ac` |
| Address | 192.168.1.59/24 |
| Assignment | DHCP with a **UniFi fixed-IP reservation** on the MAC above (set 2026-09-28) |
| Gateway | 192.168.1.1 (Ubiquiti UDM) |
| Hostname | `MOTHERLODE` (`MOTHERLODE.localdomain`) |

History: the address was .64 originally and .124 on 2026-09-14 before the reservation existed.
The reservation is confirmed once the address survives the Checkpoint 2 reboot.

## LAN clients

| Name | Address | Notes |
|---|---|---|
| ZEPHYR (Windows) | 192.168.1.64 (DHCP, `Zephyr.localdomain`) | MAC `d8:cb:8a:3e:df:6b`, workgroup `DIAMOND_DOGS`. Maps all five Samba shares. 192.168.1.64 was MOTHERLODE's historical address; it now belongs to ZEPHYR. |

## Listening services (2026-09-28, Samba added 2026-10-04)

| Port | Service | Bound to |
|---|---|---|
| 22/tcp | OpenSSH (`ssh.service`, enabled) | all interfaces |
| 11434/tcp | Ollama | 127.0.0.1 only |
| 139, 445/tcp | Samba `smbd` (2026-10-04) | all interfaces |
| 137, 138/udp | Samba `nmbd` NetBIOS names | all interfaces |
| 3702, 5355/udp | `wsdd2` WS-Discovery + LLMNR | all interfaces |

Nothing is exposed to the internet. No port forwards on the UDM.

## Remote access (planned, Checkpoint 6)

Tailscale with MagicDNS is the only intended path in from outside the LAN.
MagicDNS name `motherlode.tailb6c0f2.ts.net`, tailnet address `100.111.72.91` (unchanged after the
2026-10-04 reinstall). Tailscale SSH on, no subnet routes. **Funnel on since 2026-10-06: `https://motherlode.tailb6c0f2.ts.net`
(443) → Nextcloud on `127.0.0.1:11000` is public.** Nothing else is public, and nothing is
port-forwarded on the router. Details: `docs/services/tailscale.md`, `docs/services/nextcloud.md`.
No DuckDNS, no dynamic-DNS cron, no public ports.

## DNS (planned, Checkpoint 12)

AdGuard Home on MOTHERLODE, advertised to the LAN through the UDM's DHCP settings.
Until then clients use the UDM's resolver.

## Rules

- Persistent configuration references the MAC or the reserved address, never the DHCP-assigned one at the time.
- Home Assistant stays on the Raspberry Pi; MOTHERLODE does not host it.
- Never commit Tailscale auth keys or UniFi credentials.
