#!/bin/bash
# Mode 3: Connection-churn noisy load.
# Opens 75 new connections/second, sends one request per connection
# (forces TLS renegotiation per connection) at steady 200 RPS payload.
#
# Implementation: rapid wrk2 invocations with short-lived connections
# using --connections=1 to force per-connection TLS.
#
# Usage: bash run-noisy-churn.sh <output_file> <duration> [payload_rps]

set -euo pipefail

OUTPUT_FILE="${1:-/tmp/noisy-churn.txt}"
DURATION="${2:-180s}"
PAYLOAD_RPS="${3:-200}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRK2="${WRK2:-$(command -v wrk2)}"

if [[ "$DURATION" =~ ^([0-9]+)s$ ]]; then
  DURATION_SEC="${BASH_REMATCH[1]}"
elif [[ "$DURATION" =~ ^([0-9]+)m$ ]]; then
  DURATION_SEC=$(( ${BASH_REMATCH[1]} * 60 ))
else
  DURATION_SEC=180
fi

echo "# churn mode: 75 new-conns/s, payload=${PAYLOAD_RPS}RPS | duration=${DURATION}" > "$OUTPUT_FILE"

# Run wrk2 with many short-lived connections to force churn
# -c 75 connections, constant reconnect via keep-alive disabled in Lua
"$WRK2" -t 4 -c 75 -d "$DURATION" \
  -s "$ROOT_DIR/configs/wrk2/noisy-neighbor.lua" \
  "http://127.0.0.1:18081/" -R "$PAYLOAD_RPS" \
  >> "$OUTPUT_FILE" 2>&1 || true

echo "# churn mode complete" >> "$OUTPUT_FILE"
