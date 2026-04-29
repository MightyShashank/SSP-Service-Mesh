#!/bin/bash
# Capture node-level stats: nethogs, iostat, vmstat.
# Runs in background during measurement window.
#
# Usage: bash capture-node-stats.sh <output_dir>

set -euo pipefail

OUTPUT_DIR="${1:-/tmp/node-stats}"
mkdir -p "$OUTPUT_DIR"

log() { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }

log "Capturing node-level stats to $OUTPUT_DIR..."

# vmstat (CPU, memory, I/O) — 1 second interval
if command -v vmstat > /dev/null 2>&1; then
  vmstat 1 > "$OUTPUT_DIR/vmstat.txt" 2>/dev/null &
  PID_VMSTAT=$!
  log "vmstat started (PID: $PID_VMSTAT)"
else
  warn "vmstat not found — skipping"
  PID_VMSTAT=""
fi

# iostat (disk I/O) — 5 second interval
if command -v iostat > /dev/null 2>&1; then
  iostat -x 5 > "$OUTPUT_DIR/iostat.txt" 2>/dev/null &
  PID_IOSTAT=$!
  log "iostat started (PID: $PID_IOSTAT)"
else
  warn "iostat not found — skipping"
  PID_IOSTAT=""
fi

# nethogs (per-process network I/O) — requires root
if command -v nethogs > /dev/null 2>&1; then
  nethogs -t > "$OUTPUT_DIR/nethogs.txt" 2>/dev/null &
  PID_NETHOGS=$!
  log "nethogs started (PID: $PID_NETHOGS)"
else
  warn "nethogs not found — skipping (install: apt install nethogs)"
  PID_NETHOGS=""
fi

# Write PIDs to file for cleanup
{
  [[ -n "$PID_VMSTAT" ]]  && echo "vmstat:$PID_VMSTAT"
  [[ -n "$PID_IOSTAT" ]]  && echo "iostat:$PID_IOSTAT"
  [[ -n "$PID_NETHOGS" ]] && echo "nethogs:$PID_NETHOGS"
} > "$OUTPUT_DIR/capture-pids.txt"

log "Node stats capture running. Kill with:"
echo "  kill \$(cat $OUTPUT_DIR/capture-pids.txt | cut -d: -f2 | tr '\n' ' ')"
