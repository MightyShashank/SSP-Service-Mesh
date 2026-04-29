#!/bin/bash
# Mode 2: Burst noisy load — 200ms at 1500 RPS, 800ms quiet, repeating.
# Drives svc-noisy backend with bursty traffic pattern.
# Runs until duration elapses then exits cleanly.
#
# Usage: bash run-noisy-burst.sh <output_file> <duration>
# Example: bash run-noisy-burst.sh /tmp/noisy-burst.txt 180s

set -euo pipefail

OUTPUT_FILE="${1:-/tmp/noisy-burst.txt}"
DURATION="${2:-180s}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRK2="${WRK2:-$(command -v wrk2)}"

# Convert duration to seconds
if [[ "$DURATION" =~ ^([0-9]+)s$ ]]; then
  DURATION_SEC="${BASH_REMATCH[1]}"
elif [[ "$DURATION" =~ ^([0-9]+)m$ ]]; then
  DURATION_SEC=$(( ${BASH_REMATCH[1]} * 60 ))
else
  DURATION_SEC=180
fi

echo "# burst mode: 200ms@1500RPS / 800ms quiet | duration=${DURATION}" > "$OUTPUT_FILE"

END_TIME=$(( $(date +%s) + DURATION_SEC ))

while [[ $(date +%s) -lt $END_TIME ]]; do
  # Burst: 200ms = 0.2s
  REMAINING=$(( END_TIME - $(date +%s) ))
  [[ $REMAINING -le 0 ]] && break
  BURST_DUR=$(( REMAINING < 1 ? 1 : 1 ))  # minimum 1s wrk2 window

  "$WRK2" -t 2 -c 100 -d "1s" \
    -s "$ROOT_DIR/configs/wrk2/noisy-neighbor.lua" \
    "http://127.0.0.1:18081/" -R 1500 >> "$OUTPUT_FILE" 2>&1 || true

  # Quiet: 800ms
  sleep 0.8
done

echo "# burst mode complete" >> "$OUTPUT_FILE"
