#!/bin/bash
# Warmup script for Experiment 12.
# Runs 60 seconds of traffic on all 3 DSB endpoints simultaneously.
# Output is DISCARDED — warmup is only to stabilize:
#   - JIT compilation in Go/Java DSB services
#   - TCP connection pool warm-up (persistent connections to NGINX)
#   - Redis cache warming (home-timeline cache hot)
#   - MongoDB index loading into memory
#
# Usage: bash warmup.sh <nginx_ip> [duration]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NGINX_IP="${1:-}"
DURATION="${2:-60s}"

WRK2="${WRK2:-$(command -v wrk2)}"    # override with WRK2= env var

log()  { echo -e "\n[INFO] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

[[ -n "$NGINX_IP" ]] || fail "Usage: $0 <nginx_ip> [duration]"
[[ -x "$WRK2" ]]     || fail "wrk2 binary not found at $WRK2 — set WRK2= env var"

log "Starting warmup (${DURATION}) on all 3 endpoints — output discarded..."

"$WRK2" -t 2 -c 50 -d "$DURATION" \
  -s "$ROOT_DIR/configs/wrk2/compose-post.lua" \
  "http://127.0.0.1:18080/wrk2-api/post/compose" -R 200 > /dev/null 2>&1 &
PID1=$!

"$WRK2" -t 2 -c 50 -d "$DURATION" \
  -s "$ROOT_DIR/configs/wrk2/read-home-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/home-timeline/read" -R 300 > /dev/null 2>&1 &
PID2=$!

"$WRK2" -t 2 -c 50 -d "$DURATION" \
  -s "$ROOT_DIR/configs/wrk2/read-user-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/user-timeline/read" -R 300 > /dev/null 2>&1 &
PID3=$!

wait $PID1 $PID2 $PID3 || true   # Warmup errors are non-fatal

tick "Warmup complete (${DURATION})"
