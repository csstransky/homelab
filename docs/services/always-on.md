# Always-on: MOTHERLODE never sleeps

**Set:** 2026-09-29. A NAS that suspends is a NAS that is down, and overnight burn-in tests die with it.

## What is configured

| Layer | Setting | Where |
|---|---|---|
| systemd | `sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target` masked (linked to `/dev/null`). Nothing can suspend the machine, not even `systemctl suspend`. | `/etc/systemd/system/*.target` symlinks |
| logind | Suspend/hibernate keys, lid switch and idle action all `ignore` | `/etc/systemd/logind.conf.d/nas-always-on.conf` |
| XFCE power manager | Inactivity sleep set to never (value `0`) on AC and battery; lid handling off. Screen blanking and monitor power-off (DPMS) off since 2026-10-04 (see below). | xfconf channel `xfce4-power-manager` |

Verify:

```bash
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target   # all "masked"
busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspend   # s "no"
xfconf-query -c xfce4-power-manager -l -v
```

The logind drop-in takes effect on the next boot (logind was not restarted to avoid
disturbing the running session); the masks are effective immediately.

## 2026-10-04: XFCE "Power Manager: Timeout was reached"

**Symptom:** XFCE popup *Power Manager … Timeout was reached*, then a polkit password prompt to suspend.

**Evidence:** `~/.xsession-errors`:
`Failed to suspend via systemd: Timeout was reached` (20:05:34, ~16 min after login), then after the
password prompt `Failed to suspend/hibernate: Child process exited with code 1` (20:10:35). The
machine did not sleep: logind refused because `suspend.target` is masked, and the pm-helper
fallback failed too.

**Root cause:** the 2026-09-29 setting was wrong. In xfce4-power-manager 4.20 only `0` means
never (`src/xfpm-manager.c`, `if (on_ac == 0) … never`); any other value is minutes. `14` meant
*suspend after 14 minutes idle*. The old "14 = Never" slider convention is from older XFCE.

**Fix:**

```bash
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -s 0
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-battery -s 0
```

Applied live (the running power manager reacts to the xfconf change). Verify that
`xfconf-query -c xfce4-power-manager -lv` shows `0` for both, and that `~/.xsession-errors` gets
no new `Failed to suspend` line after 30+ idle minutes.

**Prevention:** the systemd masks are the real guarantee and they held. Desktop-level settings
are a convenience layer; check the source of the installed version rather than an old
convention.

## 2026-10-04: "it sleeps after 15 minutes" (screen, not the machine)

**Symptom:** the desktop looked asleep after ~15 idle minutes and needed the password to come back.

**Evidence:** no suspend in the journal after 20:10, and phone SSH/SMB over Tailscale kept working
through it. `xset q`: screensaver timeout 600 s, DPMS standby 600 s, off 900 s.
`light-locker` was running, which locks the session when the screensaver starts.

**Root cause:** the X screensaver blanked at 10 min and DPMS powered the monitor off at 15 min, then
light-locker locked the session. The machine itself stayed up (the suspend targets are masked).

**Fix:**

```bash
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -n -t bool -s false
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -n -t int -s 0
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-sleep -n -t uint -s 0
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off -n -t uint -s 0
xset s off; xset s noblank; xset -dpms     # running session, immediately
```

**Verification:** `xset q` shows `timeout: 0` and `DPMS is Disabled`.

**Correction (after the 23:02 reboot):** DPMS stayed off, but the X screensaver timeout came back as
600 s; the power manager does not reset it. Fixed with an XFCE autostart entry,
`~/.config/autostart/no-screen-blank.desktop`, which runs `xset s off; xset s noblank; xset -dpms`
5 s after login.

**Note:** with blanking off, light-locker never triggers, so the screen does not lock by itself.
Lock by hand with `light-locker-command -l` (or the XFCE menu) if needed. The monitor now stays
on; turn it off with its own button.

## Still to do in BIOS (F10 at POST)

- **Advanced → Power → After Power Loss: Power On** so the NAS comes back after an outage.
- Leave Wake-on-LAN enabled on the onboard NIC.
- Disable any "S4/S5 Maximum Power Savings" or deep-sleep option so WoL and the RTC keep working.

## Undo

```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo rm /etc/systemd/logind.conf.d/nas-always-on.conf
```
