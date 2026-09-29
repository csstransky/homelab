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

## Listening services (2026-09-28)

| Port | Service | Bound to |
|---|---|---|
| 22/tcp | OpenSSH (`ssh.service`, enabled) | all interfaces |
| 11434/tcp | Ollama | 127.0.0.1 only |

Nothing is exposed to the internet. No port forwards on the UDM.

## Remote access (planned, Checkpoint 6)

Tailscale with MagicDNS is the only intended path in from outside the LAN.
Previous MagicDNS name was `motherlode.tailb6c0f2.ts.net`; record the current one when Tailscale is reinstalled.
No DuckDNS, no dynamic-DNS cron, no public ports.

## DNS (planned, Checkpoint 12)

AdGuard Home on MOTHERLODE, advertised to the LAN through the UDM's DHCP settings.
Until then clients use the UDM's resolver.

## Rules

- Persistent configuration references the MAC or the reserved address, never the DHCP-assigned one at the time.
- Home Assistant stays on the Raspberry Pi; MOTHERLODE does not host it.
- Never commit Tailscale auth keys or UniFi credentials.
