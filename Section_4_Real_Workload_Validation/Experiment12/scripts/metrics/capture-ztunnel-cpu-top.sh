#!/bin/bash
# Poll ztunnel pod CPU+Memory via 'kubectl top' every INTERVAL seconds.
# Produces a timestamped TSV that cpu_plots.py can parse.
# Runs until killed (SIGTERM from parent).
#
# Usage: bash capture-ztunnel-cpu-top.sh <output_file> [interval_seconds]
# Example: bash capture-ztunnel-cpu-top.sh data/raw/run_001/ztunnel-top.txt 5

set -euo pipefail

OUTPUT_FILE="${1:-/tmp/ztunnel-top.txt}"
INTERVAL="${2:-5}"   # seconds between samples
NAMESPACE="istio-system"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# Header
{
  echo "# ztunnel kubectl top time-series"
  echo "# timestamp  pod_name  cpu_millicores  mem_mib"
  echo "# Interval: ${INTERVAL}s"
  echo "# Started: $(date -Iseconds)"
} > "$OUTPUT_FILE"

echo "[INFO] ztunnel CPU poller started → $OUTPUT_FILE (every ${INTERVAL}s)"

while true; do
  TS=$(date -Iseconds)
  # Get one line per ztunnel pod: NAME  CPU(cores)  MEMORY(bytes)
  kubectl top pod -n "$NAMESPACE" --no-headers 2>/dev/null \
    | grep -i "ztunnel" \
    | while read -r pod cpu mem; do
        # Strip units: "123m" → 123, "45Mi" → 45
        cpu_m=$(echo "$cpu" | sed 's/m//')
        mem_mi=$(echo "$mem" | sed 's/Mi//' | sed 's/Ki//' )
        echo -e "${TS}\t${pod}\t${cpu_m}\t${mem_mi}"
      done >> "$OUTPUT_FILE" 2>/dev/null || true
  sleep "$INTERVAL"
done
