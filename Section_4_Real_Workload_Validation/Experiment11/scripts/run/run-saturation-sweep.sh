#!/bin/bash
# Experiment 11 — Saturation sweep for compose-post (plain K8s).
# Sweeps compose-post from 50 → 600 RPS to find the P99 knee.
# Run ONCE before the 5-repetition baseline.
# Output: data/raw/saturation-sweep/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/configs/wrk2/saturation-sweep.env"

NAMESPACE="dsb-exp11"
SWEEP_DIR="$ROOT_DIR/data/raw/saturation-sweep"
mkdir -p "$SWEEP_DIR"

WRK2="${WRK2:-$(command -v wrk2)}"

log() { echo -e "\n[SWEEP] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Starting saturation sweep: ${START_RPS} → ${MAX_RPS} RPS (step ${STEP_RPS}, ${STEP_DURATION} each)"
log "Mode: plain Kubernetes — NO Istio"

# Port-forward
pkill -f "kubectl port-forward svc/nginx-thrift 18080:8080" || true
kubectl port-forward svc/nginx-thrift 18080:8080 -n "$NAMESPACE" &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT
sleep 3
tick "Port-forward ready"

RPS=$START_RPS
while [[ "$RPS" -le "$MAX_RPS" ]]; do
  log "Sweep point: ${RPS} RPS..."
  OUT="$SWEEP_DIR/rps-${RPS}.txt"

  "$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$STEP_DURATION" -L \
    -s "$ROOT_DIR/configs/wrk2/compose-post.lua" \
    "http://127.0.0.1:18080/wrk2-api/post/compose" -R "$RPS" \
    > "$OUT" 2>&1

  # Extract P99 for quick feedback
  P99=$(grep "99.000" "$OUT" | awk '{print $2}' | head -1 || echo "N/A")
  echo "  RPS=${RPS}  P99=${P99}"

  RPS=$(( RPS + STEP_RPS ))
  sleep 5
done

tick "Saturation sweep complete → $SWEEP_DIR"
