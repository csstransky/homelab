#!/bin/bash
# Who logged in to Nextcloud, and from which IP. Reads the audit log (admin_audit app)
# plus the main log (failed logins, brute-force throttling).
# Usage: nc-logins [N, default 30] [--failed]
n=${1:-30}
pattern='Login successful|Login failed'
[ "$2" = "--failed" ] && pattern='Login failed|Bruteforce|throttl'
docker exec nextcloud-aio-nextcloud cat /var/www/html/data/audit.log /var/www/html/data/nextcloud.log 2>/dev/null |
python3 -c '
import json, re, sys
pat, n = re.compile(sys.argv[1], re.I), int(sys.argv[2])
rows = set()
for line in sys.stdin:
    try: j = json.loads(line)
    except ValueError: continue
    m = j.get("message", "")
    if pat.search(m) and not m.startswith("Console command"):
        rows.add((j.get("time", ""), j.get("remoteAddr", ""), j.get("message", "")[:70]))
for r in sorted(rows)[-n:]:
    print("%-25s  %-26s  %s" % r)
' "$pattern" "$n"
