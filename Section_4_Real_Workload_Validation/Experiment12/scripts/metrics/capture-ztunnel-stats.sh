#!/bin/bash
# Capture ztunnel per-thread CPU utilization from /proc/{pid}/task/{tid}/stat
# Polls every 1 second and appends to output file.
# Run in background during experiment measurement window.
#
# Usage: bash capture-ztunnel-stats.sh <ztunnel_pod> <ztunnel_pid> <output_file>

set -euo pipefail

ZTUNNEL_POD="${1:-}"
ZTUNNEL_PID="${2:-}"
OUTPUT_FILE="${3:-/tmp/ztunnel-cpu.txt}"

[[ -n "$ZTUNNEL_POD" ]] || { echo "[ERROR] Usage: $0 <ztunnel_pod> <ztunnel_pid> <output_file>"; exit 1; }
[[ -n "$ZTUNNEL_PID" ]] || { echo "[ERROR] ztunnel PID required"; exit 1; }

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "# ztunnel per-thread CPU stats (polled every 1s)" > "$OUTPUT_FILE"
echo "# Pod: $ZTUNNEL_POD  PID: $ZTUNNEL_PID" >> "$OUTPUT_FILE"
echo "# Format: timestamp | tid | utime | stime | (fields from /proc/pid/task/tid/stat)" >> "$OUTPUT_FILE"
echo "# Started: $(date)" >> "$OUTPUT_FILE"

# Poll until killed (SIGTERM/SIGINT from parent)
while true; do
  TS=$(date +"%Y-%m-%dT%H:%M:%S")
  # Read all thread stat files inside the ztunnel pod
  kubectl exec -n istio-system "$ZTUNNEL_POD" -- \
    sh -c "for tid in \$(ls /proc/${ZTUNNEL_PID}/task/ 2>/dev/null); do
             echo \"$TS \$tid \$(cat /proc/${ZTUNNEL_PID}/task/\$tid/stat 2>/dev/null || echo 'unavailable')\"
           done" \
    >> "$OUTPUT_FILE" 2>/dev/null || true
  echo "---" >> "$OUTPUT_FILE"
  sleep 1
done
