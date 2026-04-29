#!/bin/bash
# Run wrk2 for read-user-timeline endpoint only (300 RPS, 180s).
# Usage: bash run-baseline-user-timeline.sh <nginx_ip> <output_file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NGINX_IP="${1:-}"
OUTPUT_FILE="${2:-user-timeline.txt}"
WRK2="${WRK2:-$ROOT_DIR/../wrk2/wrk}"

source "$ROOT_DIR/configs/wrk2/rates.env"

[[ -n "$NGINX_IP" ]] || { echo "Usage: $0 <nginx_ip> [output_file]"; exit 1; }
[[ -x "$WRK2" ]]     || { echo "[ERROR] wrk2 not found at $WRK2"; exit 1; }

echo "[INFO] user-timeline: ${USER_RPS} RPS for ${MEASURE_DURATION}"

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L \
  -s "$ROOT_DIR/configs/wrk2/read-user-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/user-timeline/read" -R "$USER_RPS" \
  > "$OUTPUT_FILE" 2>&1

echo "[INFO] user-timeline complete → $OUTPUT_FILE"
