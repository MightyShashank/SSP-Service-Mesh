#!/bin/bash
# Capture ztunnel RSS (Resident Set Size) from /proc/{pid}/smaps_rollup
# Polls every 5 seconds and appends to output file.
# Run in background during experiment measurement window.
#
# Usage: bash capture-ztunnel-rss.sh <ztunnel_pod> <ztunnel_pid> <output_file>

set -euo pipefail

ZTUNNEL_POD="${1:-}"
ZTUNNEL_PID="${2:-}"
OUTPUT_FILE="${3:-/tmp/ztunnel-rss.txt}"

[[ -n "$ZTUNNEL_POD" ]] || { echo "[ERROR] Usage: $0 <ztunnel_pod> <ztunnel_pid> <output_file>"; exit 1; }
[[ -n "$ZTUNNEL_PID" ]] || { echo "[ERROR] ztunnel PID required"; exit 1; }

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "# ztunnel RSS (polled every 5s via /proc/{pid}/smaps_rollup)" > "$OUTPUT_FILE"
echo "# Pod: $ZTUNNEL_POD  PID: $ZTUNNEL_PID" >> "$OUTPUT_FILE"
echo "# Started: $(date)" >> "$OUTPUT_FILE"

while true; do
  TS=$(date +"%Y-%m-%dT%H:%M:%S")
  echo "=== $TS ===" >> "$OUTPUT_FILE"
  kubectl exec -n istio-system "$ZTUNNEL_POD" -- \
    sh -c "cat /proc/${ZTUNNEL_PID}/smaps_rollup 2>/dev/null | grep -E 'Rss|Pss|Swap'" \
    >> "$OUTPUT_FILE" 2>/dev/null || echo "  [unavailable]" >> "$OUTPUT_FILE"
  sleep 5
done
