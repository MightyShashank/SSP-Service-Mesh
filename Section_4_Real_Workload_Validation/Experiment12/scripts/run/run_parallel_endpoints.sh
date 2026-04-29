#!/bin/bash
# Launch all 3 wrk2 instances in parallel.
# Used by run-experiment.sh and also available for standalone use.
#
# Usage: bash run_parallel_endpoints.sh <nginx_ip> <output_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NGINX_IP="${1:-}"
OUTPUT_DIR="${2:-/tmp/wrk2-output}"

[[ -n "$NGINX_IP" ]] || { echo "Usage: $0 <nginx_ip> <output_dir>"; exit 1; }

source "$ROOT_DIR/configs/wrk2/rates.env"
WRK2="${WRK2:-$ROOT_DIR/../wrk2/wrk}"
[[ -x "$WRK2" ]] || { echo "[ERROR] wrk2 not found at $WRK2"; exit 1; }

mkdir -p "$OUTPUT_DIR"

echo "[INFO] Launching 3 wrk2 instances in parallel..."
echo "  compose-post    → ${COMPOSE_RPS} RPS"
echo "  home-timeline   → ${HOME_RPS} RPS"
echo "  user-timeline   → ${USER_RPS} RPS"
echo "  Duration:       ${MEASURE_DURATION}"
echo "  Output:         $OUTPUT_DIR"

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L \
  -s "$ROOT_DIR/configs/wrk2/compose-post.lua" \
  "http://127.0.0.1:18080/wrk2-api/post/compose" -R "$COMPOSE_RPS" \
  > "$OUTPUT_DIR/compose-post.txt" 2>&1 &
PID_COMPOSE=$!

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L \
  -s "$ROOT_DIR/configs/wrk2/read-home-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/home-timeline/read" -R "$HOME_RPS" \
  > "$OUTPUT_DIR/home-timeline.txt" 2>&1 &
PID_HOME=$!

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L \
  -s "$ROOT_DIR/configs/wrk2/read-user-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/user-timeline/read" -R "$USER_RPS" \
  > "$OUTPUT_DIR/user-timeline.txt" 2>&1 &
PID_USER=$!

wait $PID_COMPOSE || echo "[WARN] compose-post wrk2 error"
wait $PID_HOME    || echo "[WARN] home-timeline wrk2 error"
wait $PID_USER    || echo "[WARN] user-timeline wrk2 error"

echo "[INFO] All 3 endpoints complete → $OUTPUT_DIR"
