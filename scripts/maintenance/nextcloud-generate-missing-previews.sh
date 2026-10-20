#!/bin/bash
# Make the thumbnails Nextcloud is missing, so opening a big folder (Pictures: ~1,400 items) does not
# make the server render hundreds of them on the spot while the page hangs. Nextcloud only renders a
# preview when someone views the file, and files added over Samba never trigger it.
# Makes the 64x64 (list view) and 256x256 (grid view) previews; the first also makes the large one
# the photo viewer uses. About 1 s per file. Pictures first, newest first, until the time limit.
# Files that fail (corrupt, unsupported) are remembered and skipped on later runs.
# See docs/recovery/2026-10-20-NEXTCLOUD-PICTURES-FREEZE.md.
# Usage: nextcloud-generate-missing-previews             run for up to 2.5 hours
#        nextcloud-generate-missing-previews 600         run for up to 600 seconds
#        nextcloud-generate-missing-previews --dry-run   only count what is missing (changes nothing)
set -euo pipefail

max_seconds=9000
failed_list=/var/lib/nextcloud-generate-missing-previews/failed-fileids

psql() {
  docker exec nextcloud-aio-database sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 "$@"' sh "$@"
}

# The shares (local::/srv/nas/...) and admin's own files. Not local::/mnt/ncdata/ (Nextcloud's internals).
missing_query="
  from oc_filecache f
  join oc_storages s on s.numeric_id = f.storage
  join oc_mimetypes m on m.id = f.mimetype
  where (s.id like 'local::/srv/nas/%' or s.id like 'home::%')
    and (m.mimetype like 'image/%' or m.mimetype like 'video/%' or m.mimetype = 'application/pdf')
    and not exists (select 1 from oc_previews p where p.file_id = f.fileid)"

if [ "${1:-}" = "--dry-run" ]; then
  psql -c "select replace(s.id, 'local::/srv/nas/', '') as share, count(*) as missing $missing_query group by 1 order by 1"
  echo "Known failures skipped: $(cat "$failed_list" 2>/dev/null | wc -l)"
  exit 0
fi
[ -n "${1:-}" ] && max_seconds=$1

mkdir -p "$(dirname "$failed_list")"
touch "$failed_list"

ids=$(psql -At -c "select f.fileid $missing_query
  order by (s.id = 'local::/srv/nas/Pictures/') desc, f.mtime desc" | grep -vxFf "$failed_list" || true)

done_count=0 failed_count=0
for id in $ids; do
  if [ "$SECONDS" -ge "$max_seconds" ]; then
    echo "Time limit reached; the rest is left for the next run."
    break
  fi
  if docker exec --user www-data nextcloud-aio-nextcloud php occ preview:generate -q -s 64x64 -s 256x256 -c "$id"; then
    done_count=$((done_count + 1))
  else
    echo "$id" >> "$failed_list"
    failed_count=$((failed_count + 1))
    echo "failed: file $id"
  fi
done

echo "Made previews for $done_count files, $failed_count failed, in $SECONDS s. Missing before this run: $(echo "$ids" | grep -c . || true)."
