#!/bin/bash
# Saturation sweep: identify P99 knee for each DSB endpoint.
# Run ONCE before the 5-repetition baseline to confirm operating point.
#
# Usage: ./run-saturation-sweep.sh [min_rps] [max_rps] [step]
# Defaults: 50 to 600 in steps of 50

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp"
WRK2="${WRK2:-$(command -v wrk2)}"

RPS_MIN="${1:-50}"
RPS_MAX="${2:-600}"
RPS_STEP="${3:-50}"
STEP_DURATION="60s"
COOLDOWN_S=30

SWEEP_DIR="$ROOT_DIR/data/raw/saturation-sweep"
mkdir -p "$SWEEP_DIR"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Saturation sweep: compose-post from ${RPS_MIN} to ${RPS_MAX} RPS (step ${RPS_STEP})"
log "Output: $SWEEP_DIR"

[[ -x "$WRK2" ]] || fail "wrk2 binary not found at $WRK2 — set WRK2= env var"

# Automatically start port-forward in the background
log "Ensuring port-forward is running on localhost:18080..."
pkill -f "kubectl port-forward svc/nginx-thrift 18080:8080" || true
kubectl port-forward svc/nginx-thrift 18080:8080 -n "$NAMESPACE" &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT
sleep 3

for RPS in $(seq "$RPS_MIN" "$RPS_STEP" "$RPS_MAX"); do
  echo ""
  echo "--- Sweeping compose-post at ${RPS} RPS ---"

  "$WRK2" -t 2 -c 50 -d "$STEP_DURATION" -L \
    -s "$ROOT_DIR/configs/wrk2/compose-post.lua" \
    "http://127.0.0.1:18080/wrk2-api/post/compose" -R "$RPS" \
    > "$SWEEP_DIR/compose-post-${RPS}rps.txt" 2>&1

  # Extract P99 for quick display
  P99=$(grep "99.000%" "$SWEEP_DIR/compose-post-${RPS}rps.txt" | awk '{print $2}' | head -1 || echo "N/A")
  echo "  → P99 at ${RPS} RPS: ${P99}"

  log "Cooldown ${COOLDOWN_S}s before next step..."
  sleep "$COOLDOWN_S"
done

tick "Saturation sweep complete"
echo ""
echo "Results: $SWEEP_DIR"
echo "Inspect P99 vs RPS to find the knee point."
echo "Operating point (200/300/300 RPS) should be below the knee."
