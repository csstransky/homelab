#!/bin/bash
# burnin.sh — logged overnight hardware stress for MOTHERLODE.
#
# Cycles through RAM, CPU, cache and mixed "compile-like" loads forever. Every phase
# start/end and a 30 s temperature/load sample are written to the log and fsync'd, so
# after a hard freeze the last line on disk says what was running and when.
#
# Start:  sudo systemd-run --unit=burnin /home/ghost/homelab/scripts/diagnostics/burnin.sh
# Stop:   sudo systemctl stop burnin
# Logs:   /home/ghost/burnin-logs/
#
# Needs: memtester, stress-ng, lm-sensors (all in Debian).

set -u
LOGDIR=/home/ghost/burnin-logs
mkdir -p "$LOGDIR"
STAMP=$(date +%F-%H%M)
LOG="$LOGDIR/burnin-$STAMP.log"
PHASEDIR="$LOGDIR/burnin-$STAMP.phases"
mkdir -p "$PHASEDIR"
chown -R ghost:ghost "$LOGDIR"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; sync -f "$LOG" 2>/dev/null || sync; }

sample() {
  local pkg cores gpu load avail
  pkg=$(sensors coretemp-isa-0000 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print $4}')
  cores=$(sensors coretemp-isa-0000 2>/dev/null | awk '/^Core/{gsub(/[+°C]/,"",$3); printf "%s ", $3}')
  gpu=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null)
  load=$(cut -d' ' -f1-3 /proc/loadavg)
  avail=$(awk '/MemAvailable/{printf "%.1fG", $2/1048576}' /proc/meminfo)
  log "SAMPLE pkg=${pkg}C cores=[${cores% }] gpu=${gpu}C load=[$load] mem_avail=$avail"
}

sampler() { while true; do sample; sleep 30; done; }

run_phase() {
  # run_phase <name> <cmd...>  — logs START/END, captures full output to PHASEDIR
  local name=$1; shift
  local out="$PHASEDIR/$(date +%H%M%S)-$name.txt"
  log "START $name :: $*"
  "$@" > "$out" 2>&1
  local rc=$?
  local bad
  # stress-ng always prints "failed: 0"; only a nonzero count is a problem.
  bad=$(grep -aiE 'fail|error|bad|mismatch' "$out" | grep -viE 'successful|no error|0 fail|failed: 0$' | head -3 | tr '\n' ' ')
  log "END   $name rc=$rc ${bad:+PROBLEM: $bad}"
  return $rc
}

trap 'log "STOP requested, exiting"; kill 0' TERM INT

log "BURN-IN START kernel=$(uname -r) uptime=$(uptime -p) hardlockup_panic=$(cat /proc/sys/kernel/hardlockup_panic)"
sampler &

# If a standalone memtester is already running, let it finish first.
while pgrep -x memtester >/dev/null; do log "WAIT standalone memtester still running"; sleep 60; done

cycle=0
while true; do
  cycle=$((cycle+1))
  log "=== CYCLE $cycle ==="
  run_phase memtester-9G       memtester 9G 1
  run_phase vm-verify-30m      stress-ng --vm 4 --vm-bytes 70% --vm-method all --verify -t 30m --metrics-brief
  run_phase cpu-verify-20m     stress-ng --cpu 8 --cpu-method all --verify -t 20m --metrics-brief
  run_phase matrix-10m         stress-ng --matrix 8 --matrix-method all --verify -t 10m --metrics-brief
  run_phase cache-stream-10m   stress-ng --cache 4 --stream 4 --verify -t 10m --metrics-brief
  run_phase compile-like-20m   stress-ng --cpu 4 --vm 2 --vm-bytes 3G --cache 2 --io 2 --hdd 1 --hdd-bytes 2G --temp-path /home/ghost/burnin-logs -t 20m --metrics-brief
  run_phase all-heavy-30m      stress-ng --cpu 8 --cpu-method all --vm 4 --vm-bytes 60% --verify -t 30m --metrics-brief
  log "=== CYCLE $cycle complete ==="
done
