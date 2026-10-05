#!/bin/bash
# What happened before the last reboot? Run with sudo after an unexpected restart or freeze.
# Usage: sudo last-crash [boot offset, default -1 = previous boot]
b=${1:--1}

echo "== Boots"
journalctl --list-boots --no-pager | tail -5

echo; echo "== End of boot $b (last 15 lines)"
journalctl -b "$b" -n 15 --no-pager -o short-precise

echo; echo "== Kernel errors/warnings in boot $b"
journalctl -b "$b" -k -p warning --no-pager -o short-precise | grep -vE 'NVRM: No NVIDIA GPU|kernel:  |Tainted:|Hardware name:|Call Trace:|Modules linked|raw: ' | tail -25

echo; echo "== Kernel crash dumps saved by EFI pstore (newest last)"
for d in /var/lib/systemd/pstore/*/; do
  [ -d "$d" ] || continue
  e=$(basename "$d"); echo "-- $e  $(date -d @"$e" '+%F %T %Z')"
  cat "$d"*/dmesg.txt 2>/dev/null | grep -E 'BUG:|Oops:|RIP: 0010|Comm:|Kernel panic|lockup|hung_task|Machine check|Bad page' | sort -u | head -12
done

echo; echo "== Hardware errors (rasdaemon: CPU machine checks, PCIe)"
ras-mc-ctl --summary 2>/dev/null | grep -v '^$'

echo; echo "== Pools"
zpool status -x
