#!/bin/bash
# Check that every row in Nextcloud's mount table (oc_mounts) has the right mount_point_hash.
# Nextcloud 34 finds a folder's mount by xxh128(mount_point). A row whose hash is stale (e.g. a
# share renamed in SQL without updating the hash) makes that folder 404 in the web UI most of the
# time (docs/recovery/2026-10-27-NEXTCLOUD-PICTURES-404.md). Read-only. Exit code 1 if any mismatch.
# Usage: nextcloud-check-mount-hashes
docker exec nextcloud-aio-database psql -U oc_nextcloud -d nextcloud_database -At -F'|' \
  -c "select id, mount_point, mount_point_hash from oc_mounts order by mount_point" |
docker exec -i nextcloud-aio-nextcloud php -r '
$bad = 0;
while (($line = fgets(STDIN)) !== false) {
    [$id, $path, $hash] = explode("|", rtrim($line, "\n"));
    $want = hash("xxh128", $path);
    if ($want === $hash) {
        printf("ok        %s\n", $path);
    } else {
        printf("MISMATCH  %s  (row %s: stored %s, should be %s)\n", $path, $id, $hash, $want);
        $bad++;
    }
}
exit($bad ? 1 : 0);
'
