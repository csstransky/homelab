# 2026-10-08: Nextcloud shows an old (broken) photo after the file was fixed on disk

**Short version:** Nextcloud only throws away a file's thumbnails/previews when the file is
changed *through Nextcloud*. Replace a file any other way (Samba, a shell, a copy into
`/tank1tb/...`) and Nextcloud keeps showing the preview of the old file, forever. No setting
changes this in Nextcloud 34. Fix: `nc-stale-previews --fix`.

## Symptoms

- Two photos in `Photos/1985 Corvette` were truncated by an interrupted copy (bottom of the
  picture a flat gray block, RGB 128,128,128). Around 12:03 they were replaced on disk with good
  copies from the Google Drive export.
- At 12:41 the Nextcloud web viewer still showed the gray-block version of
  `1985 Corvette/20240824_140326.jpg` (fileid 226549), long after the fix. Opening the file on
  the NAS directly showed the good photo.
- Same for `1985 Corvette/TODO-SORT FOLDER/20250622_015009.jpg` (fileid 227059).

## Diagnosis and evidence

1. **The file index was correct.** `oc_filecache` already had the new size (3,846,407 bytes, not
   the truncated 1,048,576) and a new etag (`c703e151…`). So "check for changes on every access"
   on the External Storage mount worked. Nextcloud knew the file had changed.
2. **The previews were old.** The viewer shows a preview (`2048-1536-max.jpg`), not the original.
   `/tank1tb/Nextcloud/appdata_ock74ildki6n/preview/0/2/a/0/c/e/c/226549/` held previews made at
   **08:11**, while the file was still broken. The 256 px one was visibly the gray-block picture.
3. **Nextcloud recorded the mismatch but never acted on it.** Each row in `oc_previews` stores the
   file's etag at render time. For 226549 that was `fab8e314…`, the file's current one `c703e151…`.
4. **Source code (Nextcloud 34.0.4, in the container under `/var/www/html`):**
   - `lib/private/Preview/WatcherConnector.php` deletes previews only on the `\OC\Files` `postWrite`
     hook (a write *through* Nextcloud's file API: web upload, desktop/phone client, WebDAV,
     Collabora) and on a version restore.
   - `lib/private/Preview/Generator.php` *writes* `etag` into the preview row but never *compares*
     it when serving a preview.
   - `lib/private/Preview/BackgroundCleanupJob.php` only removes previews of **deleted** files.
   - A change found by the scanner or check-on-access fires none of these.

## Root cause

A design gap in Nextcloud, not a misconfiguration: previews are invalidated by Nextcloud's own
write path only. Every file in Nextcloud here is External Storage over the same folders Samba
serves (`docs/services/nextcloud.md`), so any edit made over Samba or on the host can leave a stale
preview. The trigger this time: the broken photos were browsed in Nextcloud at 08:11 (previews
rendered from the truncated files), then fixed on disk at 12:03.

(Not the cause: the replaced files kept their original 2024 modification dates, i.e. older than
the broken copies. Point 1 shows Nextcloud re-indexed them anyway.)

## Fix

```bash
OCC='docker exec --user www-data nextcloud-aio-nextcloud php occ'
# 1. make sure Nextcloud has re-indexed the changed files (opening the folder in the web UI also does it)
$OCC files:scan --path="/admin/files/Photos/1985 Corvette"
# 2. list, then delete, every preview whose etag no longer matches its file
nc-stale-previews            # read-only
nc-stale-previews --fix      # deletes the rows in oc_previews + the files under appdata_*/preview
# 3. optional: render them again now instead of on next view
$OCC preview:generate -s 2048x1536 -s 256x256 -c <fileid>
```

Then reload the page in the browser with Ctrl/Cmd+Shift+R.

`nc-stale-previews` is `scripts/diagnostics/nc-stale-previews.sh`. Delete the row **and** the file
together: a row without its file (or the reverse) is its own bug, where Nextcloud thinks a preview
exists and never regenerates it ([nextcloud/server#63513](https://github.com/nextcloud/server/issues/63513)).

**Do not use `occ preview:cleanup` for this.** It deletes every preview on the server (1,356 at the
time), all of which then re-render on view.

Done on 2026-10-08: rows and files deleted by hand for 226549 and 227059, regenerated with
`preview:generate`. The new 256 px preview shows the full odometer photo. The script, on its first
run, also found and cleared 2 more: the G37 and Kia `History Sheet.xlsx` in `/Other` (edited outside
Nextcloud).

## Verification

```text
$ nc-stale-previews
No stale previews.
```

Previews regenerated for 226549 (143,670 bytes vs. 46,200 for the gray one) and 227059 (458,274 vs.
257,125), checked visually.

## Preventing it

There is **no setting** to turn on. What was checked:

| Option | Verdict |
|---|---|
| External Storage "check for changes" | Already on (every access). Updates the file index, not previews (point 1 above). |
| `occ files:scan` / cron scan | Same: updates the index only. |
| `occ preview:generate-all` / Preview Generator app | Renders *missing* previews; skips ones that exist, stale or not. |
| `occ preview:cleanup` | Works, but wipes every preview on the server. |
| Turn off previews on the mount (`files_external:option <id> previews false`) | Works, and is the workaround people settle on in the forum threads below, but no thumbnails for the whole share. Not worth it. |
| Edit/replace files through Nextcloud (web, client, WebDAV) | Triggers `postWrite`, previews are deleted correctly. The real fix, but not how Samba is used. |

Practical rule: **after replacing existing files outside Nextcloud** (fixing corrupted photos,
re-exporting edited ones with the same name), run `nc-stale-previews --fix`. Adding new files is
fine; only *replacing* a file that already had a preview is affected.

Possible later automation (not set up): a systemd timer running `nc-stale-previews --fix` every
15 minutes. It is cheap (one SQL join over `oc_previews`) and only ever deletes cached previews.
Limit: it catches a file only after Nextcloud re-indexes it (someone opens the folder, or a
`files:scan`).

## Others with the same problem

The same behaviour is reported for years, mostly with SMB/External Storage and photos re-exported
from Lightroom under the same name. No upstream fix or setting as of Nextcloud 34:

- [Caching of photos preventing updates](https://help.nextcloud.com/t/caching-of-photos-preventing-updates/170546): external storage, Lightroom re-exports; only "fix" found was disabling previews for the folder.
- [No thumbnails for media on external shares](https://help.nextcloud.com/t/no-thumbnails-for-media-on-external-shares/159939): SMB files updated with the same name keep the old preview.
- [Nextcloud not regenerating previews when uploading changed file with the same name](https://help.nextcloud.com/t/nextcloud-not-regenerating-previews-when-uploading-changed-file-with-the-same-name/111347): unanswered.
- [Preview for images edited externally not refreshed](https://help.nextcloud.com/t/preview-for-images-edited-externally-not-refreshed/86566): blamed on browser cache there; `files:scan --all` and `preview:generate-all` did not help.
- [How to force Nextcloud to regenerate a preview](https://help.nextcloud.com/t/how-to-force-nextcloud-to-regenerate-a-preview/151060) and [Regenerate preview for specific paths](https://help.nextcloud.com/t/regenerate-preview-for-specisic-pathes/144871): wipe-everything workarounds.
- [nextcloud/server#63513](https://github.com/nextcloud/server/issues/63513) (open, NC 34): `oc_previews` rows out of sync with preview files block regeneration.
