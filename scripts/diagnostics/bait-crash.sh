#!/bin/bash
# bait-crash.sh — try to reproduce MOTHERLODE's single-bit-corruption kernel panics.
#
# The panics (docs/recovery/2026-10-04-ZFS-PANIC.md) never showed up under user-space stress
# (memtester, stress-ng, memtest86+). They came during kernel/ZFS memory activity: ARC shrink
# and eviction, zfs send/receive, ACL/xattr updates, and cores dropping into idle. This script
# runs all of those at once, at mixed intensity, for RUNTIME seconds:
#
#   arcflap   zfs_arc_max flips 3 GiB <-> 1 GiB every 10 min (the 10-04 ARC-shrink trigger)
#   sendrecv  newest daily snapshot sent into a scratch dataset on the other pool, verified
#             file by file against the source snapshot, destroyed, repeated (the 10-06 trigger)
#   sendnull  zfs send of every dataset to /dev/null (ARC/ABD churn, read only)
#   readall   cat every file on both pools to /dev/null (ARC eviction)
#   acl       recursive setfacl add/remove + user xattrs on ~scratch files (the 10-04 setfacl crash)
#   pulse     2 s CPU bursts with random idle gaps (C-state entry/exit, the 10-06 idle-path crash)
#   compact   memory compaction + drop_caches every 2 min (moves/frees many kernel pages)
#   scrub     one scrub of tank1tb and tank500gb (reads and checksums every block)
#   sat       optional (SAT=1): Google stressapptest with all threads pausing every 60 s
#             (power spikes, the idle/power-transition suspect) plus memory copy and cache tests
#
# ARC_MAX=<bytes> sets the high side of arcflap for this run only (default: the current limit).
# On 16 GB use 8 GiB, the size the ARC had when 10-04 crashed; 3 GiB is restored on exit.
#
# Real datasets are only READ. Writes go to tank1tb/baittest and tank500gb/baittest, which
# are created here and destroyed on exit. A data mismatch is logged as CORRUPTION: it means
# a bit flipped without a panic.
#
# Start:  sudo systemd-run --unit=bait -p TimeoutStopSec=300 -E RUNTIME=28800 /home/ghost/homelab/scripts/diagnostics/bait-crash.sh
# 16 GB:  sudo systemd-run --unit=bait -p TimeoutStopSec=300 -E RUNTIME=28800 -E ARC_MAX=8589934592 -E SAT=1 /home/ghost/homelab/scripts/diagnostics/bait-crash.sh
# Stop:   sudo systemctl stop bait          (cleans up, restores zfs_arc_max)
# Logs:   /home/ghost/bait-logs/  and  journalctl -t bait
# After an unexpected reboot: sudo last-crash, then rerun this script (it removes leftovers).

set -u
RUNTIME=${RUNTIME:-28800}
LOGDIR=/home/ghost/bait-logs
STAMP=$(date +%F-%H%M)
LOG="$LOGDIR/bait-$STAMP.log"
WORK="$LOGDIR/bait-$STAMP.work"
mkdir -p "$LOGDIR" "$WORK"
chown -R ghost:ghost "$LOGDIR"

SRC1=tank1tb/Photos      # sent to tank500gb/baittest/recv
SRC2=tank500gb/Music     # sent to tank1tb/baittest/recv
ARC_PARAM=/sys/module/zfs/parameters/zfs_arc_max
ARC_ORIG=$(cat "$ARC_PARAM")
ARC_MAX=${ARC_MAX:-$ARC_ORIG}
SAT=${SAT:-0}
SCRUBBED=""

log() {
  echo "$(date '+%F %T') $*" >> "$LOG"
  sync -f "$LOG" 2>/dev/null || sync
  logger -t bait -- "$*"
}

destroy_scratch() {
  local ds
  for ds in tank1tb/baittest tank500gb/baittest; do
    zfs list -H "$ds" >/dev/null 2>&1 || continue
    for try in 1 2 3 4 5; do
      zfs destroy -rf "$ds" 2>/dev/null && { log "destroyed $ds"; continue 2; }
      sleep 5
    done
    log "WARNING: could not destroy $ds, remove it by hand: sudo zfs destroy -r $ds"
  done
}

# kill_tree <pid>: kill every descendant of <pid>, deepest first (not <pid> itself)
kill_tree() {
  local c
  for c in $(pgrep -P "$1"); do kill_tree "$c"; kill "$c" 2>/dev/null; done
}

cleanup() {
  [ "$BASHPID" = "$$" ] || exit 0   # background workers inherit the trap; only the main shell cleans up
  trap - EXIT INT TERM
  log "STOP: cleaning up"
  # Only this script's own descendants. A pattern like "zfs send .*@autosnap" also matched the
  # nightly syncoid backup and killed it (zfs/BACKUPS.md, 2026-10-08).
  kill_tree $$; sleep 2; kill_tree $$
  echo "$ARC_ORIG" > "$ARC_PARAM"
  for p in $SCRUBBED; do zpool scrub -s "$p" 2>/dev/null; done
  sleep 3
  destroy_scratch
  log "zfs_arc_max restored to $ARC_ORIG; done"
  chown -R ghost:ghost "$LOGDIR"
}
trap cleanup EXIT
trap 'cleanup; exit 1' INT TERM

newest_daily() { zfs list -H -t snapshot -o name -s creation "$1" | grep '_daily$' | tail -1; }

# Hash every file under $1 (paths relative to it), sorted, into $2
manifest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) > "$2"; }

sample() {
  local pkg load avail arc
  pkg=$(sensors coretemp-isa-0000 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print $4}')
  load=$(cut -d' ' -f1-3 /proc/loadavg)
  avail=$(awk '/MemAvailable/{printf "%.1fG", $2/1048576}' /proc/meminfo)
  arc=$(awk '$1=="size"{s=$3} $1=="c_max"{c=$3} END{printf "%.2f/%.2fG", s/2^30, c/2^30}' /proc/spl/kstat/zfs/arcstats)
  log "SAMPLE pkg=${pkg}C load=[$load] mem_avail=$avail arc=$arc"
}

arcflap() {
  while true; do
    echo $((1 << 30)) > "$ARC_PARAM"; log "arcflap: arc_max 1 GiB"; sleep 600
    echo "$ARC_MAX" > "$ARC_PARAM"; log "arcflap: arc_max $((ARC_MAX >> 20)) MiB"; sleep 600
  done
}

sendrecv() {
  # sendrecv <source dataset> <scratch parent>
  local src=$1 parent=$2 snap dst n=0
  dst="$parent/recv"
  while true; do
    n=$((n + 1))
    snap=$(newest_daily "$src")
    zfs list -H "$dst" >/dev/null 2>&1 && zfs destroy -r "$dst"
    log "sendrecv[$src] #$n: $snap -> $dst"
    if ! zfs send -L "$snap" | zfs receive -u "$dst"; then
      log "sendrecv[$src] #$n: send/receive FAILED"; sleep 60; continue
    fi
    zfs set readonly=on "$dst"; zfs mount "$dst"
    manifest "/$src/.zfs/snapshot/${snap#*@}" "$WORK/$n-${src//\//_}-src.sha"
    manifest "$(zfs get -H -o value mountpoint "$dst")" "$WORK/$n-${src//\//_}-dst.sha"
    if cmp -s "$WORK/$n-${src//\//_}-src.sha" "$WORK/$n-${src//\//_}-dst.sha"; then
      log "sendrecv[$src] #$n: verified $(wc -l < "$WORK/$n-${src//\//_}-dst.sha") files OK"
      rm -f "$WORK/$n-${src//\//_}-"*.sha
    else
      log "CORRUPTION sendrecv[$src] #$n: copy differs from source, see $WORK/$n-*"
    fi
  done
}

sendnull() {
  local ds snap
  while true; do
    for ds in tank1tb/Documents tank1tb/Music tank1tb/Apps tank500gb/Photos tank500gb/Documents; do
      snap=$(newest_daily "$ds")
      log "sendnull: $snap"
      zfs send -L "$snap" > /dev/null || log "sendnull: $snap FAILED"
    done
  done
}

readall() {
  local pool
  while true; do
    for pool in /tank1tb /tank500gb; do
      log "readall: $pool"
      find "$pool" -path "$pool/baittest" -prune -o -type f -print0 2>/dev/null \
        | xargs -0 -r -P 2 cat > /dev/null 2>&1
    done
    sleep 10
  done
}

acl() {
  local dir=/tank1tb/baittest/acl n=0 cnt
  zfs create -o mountpoint=$dir tank1tb/baittest/acl
  cp -a /usr/share/doc /usr/include /usr/share/locale "$dir/" 2>/dev/null
  manifest "$dir" "$WORK/acl.sha"
  log "acl: $(wc -l < "$WORK/acl.sha") files in $dir"
  while true; do
    n=$((n + 1))
    setfacl -R -m u:33:rwX "$dir"
    cnt=$(getfacl -Rn "$dir" 2>/dev/null | grep -c '^user:33:')
    find "$dir" -type f -print0 | xargs -0 -r setfattr -n user.bait -v "cycle-$n" 2>/dev/null
    find "$dir" -type f -print0 | xargs -0 -r setfattr -x user.bait 2>/dev/null
    setfacl -R -x u:33 "$dir"
    echo 3 > /proc/sys/vm/drop_caches
    if manifest "$dir" "$WORK/acl.now" && cmp -s "$WORK/acl.sha" "$WORK/acl.now"; then
      log "acl #$n: $cnt ACL entries set and removed, files verified OK"
    else
      log "CORRUPTION acl #$n: file contents changed, see $WORK/acl.sha vs acl.now"
      cp "$WORK/acl.now" "$WORK/acl.bad-$n"
    fi
  done
}

sat() {
  # -M MiB of user-space memory; pauses make every core idle at once, then resume together
  log "sat: stressapptest started"
  stressapptest -s $((RUNTIME - 300)) -M 1536 -W --cc_test --pause_delay 60 --pause_duration 15 \
    > "$WORK/stressapptest.txt" 2>&1
  log "sat: $(grep -o 'Status: .*' "$WORK/stressapptest.txt" | tail -1) ($(grep -c 'Hardware Error' "$WORK/stressapptest.txt") hardware errors)"
  grep -q 'Hardware Error' "$WORK/stressapptest.txt" && log "CORRUPTION sat: see $WORK/stressapptest.txt"
}

pulse() {
  while true; do
    setsid -w stress-ng --cpu 8 --timeout 2s --quiet >/dev/null 2>&1   # own session: stress-ng signals its process group
    sleep $((RANDOM % 8 + 1))
  done
}

compact() {
  while true; do
    sleep 120
    echo 1 > /proc/sys/vm/compact_memory
    echo 3 > /proc/sys/vm/drop_caches
  done
}

# --- start ---
log "START runtime=${RUNTIME}s arc_max=$((ARC_MAX >> 20))MiB sat=$SAT kernel=$(uname -r) mem=$(awk '/MemTotal/{printf "%.1fG", $2/1048576}' /proc/meminfo)"
log "DIMMs: $(dmidecode -t memory | awk -F': ' '/^\tLocator/{l=$2} /^\tPart Number/{if ($2 !~ /Not Specified/) printf "%s=%s ", l, $2}')"
log "pstore before: $(ls /var/lib/systemd/pstore | tr '\n' ' ')"
destroy_scratch   # leftovers from a run that crashed
zfs create -o mountpoint=/tank1tb/baittest tank1tb/baittest
zfs create -o mountpoint=/tank500gb/baittest tank500gb/baittest

SCRUBBED=""   # cancel on exit only the scrubs this script started
for p in tank1tb tank500gb; do zpool scrub "$p" 2>/dev/null && SCRUBBED="$SCRUBBED $p"; done
log "scrub: started on${SCRUBBED:- nothing (already running?)}"

arcflap &
sendrecv "$SRC1" tank500gb/baittest &
sendrecv "$SRC2" tank1tb/baittest &
sendnull &
readall &
acl &
pulse &
compact &
[ "$SAT" = 1 ] && sat &

end=$(( $(date +%s) + RUNTIME ))
while [ "$(date +%s)" -lt "$end" ]; do
  sample
  for p in tank1tb tank500gb; do
    ! zpool status "$p" | grep -q 'scrub in progress' && ! grep -q "scrub done $p" "$LOG" \
      && log "scrub done $p: $(zpool status "$p" | grep -E 'scan:|errors:' | tr -s ' ' | tr '\n' ' ')"
  done
  sleep 30
done
log "RUNTIME reached without a panic"
