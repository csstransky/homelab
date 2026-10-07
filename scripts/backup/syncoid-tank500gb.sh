#!/bin/bash
# Nightly copy of the important tank1tb datasets to the tank500gb mirror (Checkpoint 3).
# Run by syncoid-tank500gb.timer at 03:00. Repo copy: scripts/backup/syncoid-tank500gb.sh
#
# --no-sync-snap    send only sanoid's own snapshots, so tank500gb keeps the same history
# --create-bookmark leave a bookmark on the source, so the next run can stay incremental
#                   even if sanoid has already pruned the snapshot it last sent
# Copies are set readonly=on: browse them under /tank500gb/<name>, never edit them there.
set -u
DATASETS="Documents Photos Music Apps Nextcloud Backups"
rc=0
for d in $DATASETS; do
  echo "== tank1tb/$d -> tank500gb/$d"
  if /usr/sbin/syncoid --no-sync-snap --create-bookmark "tank1tb/$d" "tank500gb/$d"; then
    zfs set readonly=on "tank500gb/$d"
  else
    echo "FAILED: tank1tb/$d"
    rc=1
  fi
done
exit $rc
