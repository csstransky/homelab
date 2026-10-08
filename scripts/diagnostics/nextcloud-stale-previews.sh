#!/bin/bash
# Nextcloud previews that no longer match their file: the file was replaced outside Nextcloud
# (Samba, a shell, a copy into /tank1tb/...), so Nextcloud keeps showing the old thumbnail.
# A preview row stores the file's etag at render time; if that differs from the file's current
# etag, the preview is stale. Nextcloud 34 stores the etag but never compares it.
# See docs/recovery/2026-10-08-STALE-NEXTCLOUD-PREVIEWS.md.
# Usage: nextcloud-stale-previews          list stale previews (changes nothing)
#        nextcloud-stale-previews --fix    delete them; Nextcloud re-renders them on next view
# Only finds files Nextcloud has already re-indexed (opened folder or files:scan), see the doc.
set -euo pipefail

psql() {
  docker exec nextcloud-aio-database sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 "$@"' sh "$@"
}

stale_ids=$(psql -At -c "
  select distinct p.file_id from oc_previews p join oc_filecache f on f.fileid = p.file_id
  where trim(p.etag) <> f.etag order by 1")

if [ -z "$stale_ids" ]; then
  echo "No stale previews."
  exit 0
fi

psql -c "
  select f.fileid, replace(s.id, 'local::/srv/nas/', '') || f.path as file, count(*) as previews
  from oc_previews p join oc_filecache f on f.fileid = p.file_id
  join oc_storages s on s.numeric_id = f.storage
  where trim(p.etag) <> f.etag group by 1, 2 order by 2"

if [ "${1:-}" != "--fix" ]; then
  echo "Run with --fix to delete these previews."
  exit 0
fi

preview_root=$(ls -d /tank1tb/Nextcloud/appdata_*/preview)
for id in $stale_ids; do
  # Same layout as LocalPreviewStorage: first 7 hex digits of md5(fileid), one per folder level
  shard=$(printf %s "$id" | md5sum | cut -c1-7 | sed 's/./&\//g')
  psql -q -c "delete from oc_previews where file_id = $id"
  rm -rf "${preview_root:?}/${shard}${id}"
  echo "cleared previews of file $id"
done
