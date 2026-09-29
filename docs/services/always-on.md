# Always-on: MOTHERLODE never sleeps

**Set:** 2026-09-29. A NAS that suspends is a NAS that is down, and overnight burn-in tests die with it.

## What is configured

| Layer | Setting | Where |
|---|---|---|
| systemd | `sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target` masked (linked to `/dev/null`). Nothing can suspend the machine, not even `systemctl suspend`. | `/etc/systemd/system/*.target` symlinks |
| logind | Suspend/hibernate keys, lid switch and idle action all `ignore` | `/etc/systemd/logind.conf.d/nas-always-on.conf` |
| XFCE power manager | Inactivity sleep set to never (value `14`) on AC and battery; lid handling off. Display DPMS blanking is left on; a dark monitor is fine. | xfconf channel `xfce4-power-manager` |

Verify:

```bash
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target   # all "masked"
busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspend   # s "no"
xfconf-query -c xfce4-power-manager -l -v
```

The logind drop-in takes effect on the next boot (logind was not restarted to avoid
disturbing the running session); the masks are effective immediately.

## Still to do in BIOS (F10 at POST)

- **Advanced → Power → After Power Loss: Power On** so the NAS comes back after an outage.
- Leave Wake-on-LAN enabled on the onboard NIC.
- Disable any "S4/S5 Maximum Power Savings" or deep-sleep option so WoL and the RTC keep working.

## Undo

```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo rm /etc/systemd/logind.conf.d/nas-always-on.conf
```
