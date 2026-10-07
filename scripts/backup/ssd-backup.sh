#!/bin/bash
# Copy what lives only on the OS SSD (configs, home, root) onto ZFS, where sanoid snapshots it
# and syncoid copies it to tank500gb. Docker volumes are already on ZFS (/tank1tb/Apps/docker-volumes).
# Not copied: Docker images, packages, caches (all re-downloadable). docs/recovery/SSD-BACKUP.md
set -u
DEST=/tank1tb/Backups/motherlode-ssd
mkdir -p "$DEST" && chmod 700 "$DEST"
rc=0
copy() { echo "== $1"; rsync -aHAX --numeric-ids --delete --delete-excluded "${@:2}" "$1" "$DEST/$(echo "$1" | tr / _ | sed 's/^_//;s/_$//')/" || { echo "FAILED: $1"; rc=1; }; }
copy /etc/
copy /root/ --exclude=.cache/
copy /home/ghost/ --exclude=.cache/ --exclude=.npm/ --exclude=.local/share/Trash/
dpkg --get-selections > "$DEST/dpkg-selections.txt"
apt-mark showmanual > "$DEST/apt-manual.txt"
du -sh "$DEST"
exit $rc
