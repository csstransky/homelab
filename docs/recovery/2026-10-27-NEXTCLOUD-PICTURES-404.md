# 2026-10-27: Pictures opens empty in Nextcloud (stale mount hash from the Photos rename)

**Short version:** the Oct 9 rename of the Photos share to Pictures updated the mount's path in
`oc_mounts` but not its `mount_point_hash`. Nextcloud 34 finds a folder's mount by that hash, so most
web requests for `/Pictures` found no mount and answered **404**. Fixed by writing the right hash into
the one row. Not RAM, CPU, thumbnails or folder size.
Status: **fixed and verified** by the user (Pictures and its favourites open every time).

## Symptoms

- In the web UI, clicking **Pictures** changes the URL (`?dir=/Pictures`) but the list stays empty.
  Documents and the other shares open normally.
- Favourites inside Pictures (e.g. 1984 Corvette, 2016 Kia Forte) opened **about 10% of the time**.
- Started with the Oct 9 rename. On Oct 20 it was put down to missing thumbnails
  (`2026-10-20-NEXTCLOUD-PICTURES-FREEZE.md`); generating them all did not fix it.

## Diagnosis and evidence

Each check below ruled something out before the cause was found.

| Suspect | Check | Result |
|---|---|---|
| Missing thumbnails | `journalctl -u nextcloud-generate-missing-previews.service` | backlog done Oct 21 (8,857 made), 0 missing nightly since; still broken |
| RAM / CPU / PHP memory limit | list the folder through Nextcloud's PHP API inside the container | Pictures 1,425 entries in 0.02 s, 33 MB peak (Documents 515 in 0.01 s) |
| PHP errors | `nextcloud.log` (level 2) | nothing since Oct 21 |
| Timeouts | `max_execution_time` | 0 (none) |
| Check-on-access rescan | `occ files:scan --shallow --path=/admin/files/Pictures` | ~1 s, 0 errors (Documents 0.9 s) |
| Storage marked unavailable | `oc_storages.available` | 1 for all |
| Nextcloud bug #65766 (federated share stalls) | log for `ocm provider` | 0 hits |

The deciding evidence came from the browser: Firefox DevTools → Network, the `PROPFIND
/remote.php/dav/files/admin/Pictures/` request returned

```xml
<s:exception>Sabre\DAV\Exception\NotFound</s:exception>
<s:message>File with name /Pictures could not be located</s:message>
```

So the server was not slow; for that request Pictures did not exist. From the command line it always
existed (the full user setup loads every mount by user, not by hash). A web request only sets up the
mount for the path it asks for, via `UserMountCache::getMountForPath()`, which looks the mount up by
`mount_point_hash = xxh128(mount_point)`
(`/var/www/html/lib/private/Files/Config/UserMountCache.php`, column added in Nextcloud 33).

```text
/admin/files/Pictures/  stored hash 8449798f7a66103ab87b6c4961eaae58
xxh128('/admin/files/Photos/')    = 8449798f7a66103ab87b6c4961eaae58   ← the old name
xxh128('/admin/files/Pictures/')  = baea23256972331c7d0ec4e3f44d134c   ← what it should be
```

All other rows matched. The user's guess ("is it the Photos → Pictures rename?") was right.

## Root cause

The "Renaming a share later" procedure in `docs/services/nextcloud.md` (used 2026-10-09, commit
`16765a1`) updated `oc_mounts.mount_point` by SQL but not `mount_point_hash`. Lookups by the new
path missed, Nextcloud fell back to the home storage `/admin/`, which has no `files/Pictures`, and
returned 404. Requests that had already loaded all of admin's mounts (the ~10%) found it by path.

## Fix

```bash
sudo zfs snapshot tank1tb/Apps@pre-pictures-mount-hash-fix   # undo point (kept)
NEW=$(sudo docker exec nextcloud-aio-nextcloud php -r "echo hash('xxh128', '/admin/files/Pictures/');")
OLD=$(sudo docker exec nextcloud-aio-nextcloud php -r "echo hash('xxh128', '/admin/files/Photos/');")
sudo docker exec nextcloud-aio-database psql -U oc_nextcloud -d nextcloud_database -c \
  "update oc_mounts set mount_point_hash = '$NEW' where id = 7 and mount_point = '/admin/files/Pictures/' and mount_point_hash = '$OLD';"
# UPDATE 1
```

Compute hashes with PHP rather than typing them: the first attempt failed on a mistyped hash
(`value too long for type character varying(32)`, nothing changed).

## Verification

| Check | Result |
|---|---|
| `nextcloud-check-mount-hashes` | all 6 rows `ok` |
| Same script fed the old row | `MISMATCH ... should be baea2325...`, exit 1 |
| User, Firefox on the Mac | Pictures opens from All files and from Favourites, many times in a row |

## Preventing it

- The rename procedure in `docs/services/nextcloud.md` now updates `mount_point_hash` too and ends
  with `nextcloud-check-mount-hashes`.
- Any SQL that changes `oc_mounts.mount_point`: recompute the hash with
  `php -r "echo hash('xxh128', '<path>');"` inside the Nextcloud container.
- If one folder 404s in the web UI but `occ` sees it fine, run `nextcloud-check-mount-hashes` first.
- Look at the failing request in the browser's Network tab early: it turned a week of
  "slow folder" guesses into a 404 in one step.

## Loose ends

- The Android app requested `/Photos/` 2,311 times (audit log). Probably auto-upload or a saved
  folder still pointing at the old name; check it in the app.
- While investigating, the agent turned on debug logging for admin only
  (`log.condition users 0 admin`) and removed it the same day.
