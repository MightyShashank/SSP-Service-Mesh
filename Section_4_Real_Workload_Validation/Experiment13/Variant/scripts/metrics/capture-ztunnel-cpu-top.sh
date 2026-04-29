#!/bin/bash
# Poll ztunnel pod CPU, Memory, AND thread count via kubectl top + exec.
# Produces a timestamped TSV: timestamp | pod | cpu_m | mem_mi | thread_count
# Runs until killed (SIGTERM from parent).
#
# Usage: bash capture-ztunnel-cpu-top.sh <output_file> [interval_seconds]

# NOTE: Do NOT use set -e here — kubectl top transient failures must not kill the poller.

OUTPUT_FILE="${1:-/tmp/ztunnel-top.txt}"
INTERVAL="${2:-5}"
NAMESPACE="istio-system"

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  echo "# ztunnel kubectl top time-series"
  echo "# columns: timestamp  pod_name  cpu_millicores  mem_mib  thread_count"
  echo "# Interval: ${INTERVAL}s"
  echo "# Started: $(date -Iseconds)"
} > "$OUTPUT_FILE"

echo "[INFO] ztunnel metrics poller started → $OUTPUT_FILE (every ${INTERVAL}s)"

while true; do
  TS=$(date -Iseconds)

  TOP_OUTPUT=$(kubectl top pod -n "$NAMESPACE" --no-headers 2>/dev/null || true)

  if [[ -z "$TOP_OUTPUT" ]]; then
    echo "[WARN] $(date -Iseconds) kubectl top returned empty — metrics-server may be unavailable" >&2
    sleep "$INTERVAL"
    continue
  fi

  echo "$TOP_OUTPUT" | grep -i "ztunnel" | while read -r pod cpu mem; do
    # Normalise CPU to millicores (strip trailing 'm')
    cpu_m=$(echo "$cpu" | sed 's/m$//')

    # Normalise memory to MiB
    if echo "$mem" | grep -q 'Gi'; then
      mem_mi=$(echo "$mem" | sed 's/Gi//' | awk '{printf "%.0f", $1 * 1024}')
    elif echo "$mem" | grep -q 'Ki'; then
      mem_mi=$(echo "$mem" | sed 's/Ki//' | awk '{printf "%.0f", $1 / 1024}')
    else
      mem_mi=$(echo "$mem" | sed 's/Mi//')
    fi

    # Thread count via /proc/1/task/ inside the ztunnel container
    thread_count=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
      sh -c 'ls /proc/1/task/ 2>/dev/null | wc -l' 2>/dev/null || echo "0")
    thread_count=$(echo "$thread_count" | tr -d '[:space:]')

    echo -e "${TS}\t${pod}\t${cpu_m}\t${mem_mi}\t${thread_count}"
  done >> "$OUTPUT_FILE" 2>/dev/null

  sleep "$INTERVAL"
done
