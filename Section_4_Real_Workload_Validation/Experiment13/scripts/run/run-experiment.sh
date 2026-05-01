#!/bin/bash
# Experiment 13 — Master runner: one full trial.
#
# Collects:
#   - wrk2 latency percentiles for all 3 DSB endpoints (P50/P99/P99.9/P99.99/throughput)
#   - ztunnel metrics: CPU millicores, memory Mi, thread count (every 5s)
#   - Jaeger traces for internal service hop latency (10% sampling)
#
# Usage:
#   ./run-experiment.sh --case A --mode sustained-ramp [--noisy-rps 300]
#   ./run-experiment.sh --case B --mode burst
#   ./run-experiment.sh --case C --mode churn
#
# Output: data/raw/<case>/<mode>/trial_NNN/
#   compose-post.txt, home-timeline.txt, user-timeline.txt
#   noisy-load.txt   (wrk2 output for svc-noisy)
#   ztunnel-top.txt  (kubectl top time-series)
#   run-metadata.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─── Parse arguments ──────────────────────────────────────────────────────────
VICTIM_CASE=""
NOISY_MODE=""
NOISY_RPS=0     # Only used for sustained-ramp single-point runs

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case)   VICTIM_CASE="$2"; shift 2 ;;
    --mode)   NOISY_MODE="$2";  shift 2 ;;
    --noisy-rps) NOISY_RPS="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$VICTIM_CASE" ]] || { echo "[ERROR] --case A|B|C required"; exit 1; }
[[ -n "$NOISY_MODE"  ]] || { echo "[ERROR] --mode sustained-ramp|burst|churn required"; exit 1; }

# ─── Config ───────────────────────────────────────────────────────────────────
NAMESPACE="dsb-exp"
NAMESPACE_OBS="observability"
WORKER_0="default-pool-ssp-11b2c93c3e14"

source "$ROOT_DIR/configs/wrk2/rates.env"
source "$ROOT_DIR/configs/noisy-neighbor/modes.env"

WRK2="${WRK2:-$(command -v wrk2)}"

# Output directory: data/raw/<case>/<mode>/trial_NNN/
BASE_RAW="$ROOT_DIR/data/raw/case-${VICTIM_CASE}/${NOISY_MODE}"
mkdir -p "$BASE_RAW"
TRIAL_NUM=$(printf "%03d" $(( $(ls -d "$BASE_RAW"/trial_* 2>/dev/null | wc -l) + 1 )))
TRIAL_DIR="$BASE_RAW/trial_${TRIAL_NUM}"
mkdir -p "$TRIAL_DIR"

RUN_ID=$(date +"%Y%m%d_%H%M%S")

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

# ─── Pre-checks ───────────────────────────────────────────────────────────────
log "Experiment 13 — Case ${VICTIM_CASE} | Mode: ${NOISY_MODE} | Trial ${TRIAL_NUM}"

kubectl cluster-info > /dev/null || fail "kubectl not connected"
[[ -x "$WRK2" ]] || fail "wrk2 not found — set WRK2= or symlink"

# Verify svc-noisy is deployed
kubectl get deploy svc-noisy -n "$NAMESPACE" > /dev/null 2>&1 || \
  fail "svc-noisy not deployed — run: kubectl apply -f configs/noisy-neighbor/svc-noisy-deploy.yaml"

# ─── Port-forwards ────────────────────────────────────────────────────────────
log "Starting port-forwards..."
pkill -f "kubectl port-forward svc/nginx-thrift 18080" || true
pkill -f "kubectl port-forward svc/svc-noisy 18081"    || true
sleep 1

kubectl port-forward svc/nginx-thrift 18080:8080 -n "$NAMESPACE" &
PF_DSB=$!
kubectl port-forward svc/svc-noisy 18081:80 -n "$NAMESPACE" &
PF_NOISY=$!
trap "kill $PF_DSB $PF_NOISY 2>/dev/null || true" EXIT
sleep 3
tick "Port-forwards ready (DSB→18080, noisy→18081)"

# Jaeger port-forward for trace collection
NAMESPACE_OBS="observability"
JAEGER_READY=false
if kubectl get svc jaeger-query -n "$NAMESPACE_OBS" > /dev/null 2>&1; then
  pkill -f "kubectl port-forward svc/jaeger-query 16686" || true; sleep 1
  kubectl port-forward svc/jaeger-query 16686:16686 -n "$NAMESPACE_OBS" &
  PF_JAEGER=$!
  trap "kill $PF_DSB $PF_NOISY $PF_JAEGER 2>/dev/null || true" EXIT
  for i in $(seq 1 15); do
    curl -s --connect-timeout 2 "http://127.0.0.1:16686/api/services" > /dev/null 2>&1 && JAEGER_READY=true && break
    sleep 2
  done
  [[ "$JAEGER_READY" == "true" ]] && tick "Jaeger port-forward ready"
fi

# ─── Find ztunnel pod ────────────────────────────────────────────────────────
log "Finding ztunnel pod on worker-0..."
ZTUNNEL_POD=$(kubectl get pods -n istio-system -o wide \
  | awk -v node="$WORKER_0" '$0 ~ "ztunnel" && $7 == node {print $1}')
[[ -n "$ZTUNNEL_POD" ]] || fail "No ztunnel pod on worker-0"
tick "ztunnel pod → $ZTUNNEL_POD"

# ─── Warmup ───────────────────────────────────────────────────────────────────
# NOTE: Warmup is done ONCE at start of run-sustained-ramp.sh (not per trial).
# Cluster stays warm via 60-120s cooldowns between trials.

# ─── Start ztunnel CPU poller ─────────────────────────────────────────────────
log "Starting ztunnel metrics poller (CPU + memory + threads)..."
bash "$ROOT_DIR/scripts/metrics/capture-ztunnel-cpu-top.sh" \
  "$TRIAL_DIR/ztunnel-top.txt" 5 &
PID_TOP=$!
tick "ztunnel poller started → $TRIAL_DIR/ztunnel-top.txt"

# ─── Start DSB measurement ────────────────────────────────────────────────────
RUN_START=$(date +"%Y-%m-%d %H:%M:%S")
log "Starting DSB measurement (${MEASURE_DURATION}, all 3 endpoints in parallel)..."

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L \
  -s "$ROOT_DIR/configs/wrk2/compose-post.lua" \
  "http://127.0.0.1:18080/wrk2-api/post/compose" -R "$COMPOSE_RPS" \
  > "$TRIAL_DIR/compose-post.txt" 2>&1 &
PID_COMPOSE=$!

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L \
  -s "$ROOT_DIR/configs/wrk2/read-home-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/home-timeline/read" -R "$HOME_RPS" \
  > "$TRIAL_DIR/home-timeline.txt" 2>&1 &
PID_HOME=$!

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L \
  -s "$ROOT_DIR/configs/wrk2/read-user-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/user-timeline/read" -R "$USER_RPS" \
  > "$TRIAL_DIR/user-timeline.txt" 2>&1 &
PID_USER=$!

# ─── Start noisy load (concurrent with DSB) ──────────────────────────────────
log "Starting noisy load: mode=${NOISY_MODE} case=${VICTIM_CASE}..."

case "$NOISY_MODE" in
  sustained-ramp)
    # Single fixed RPS point — the sweep is driven by run-sustained-ramp.sh
    TARGET_NOISY="${NOISY_RPS:-100}"
    if [[ "$TARGET_NOISY" -eq 0 ]]; then
      # wrk2 rejects -R 0. At 0 RPS we want a clean baseline with no noisy load.
      # Write an explicit placeholder and sleep for the measurement duration instead.
      echo "# NOISY_RPS=0 — baseline trial, no noisy load generated" \
        > "$TRIAL_DIR/noisy-load.txt"
      log "NOISY_RPS=0 → skipping noisy wrk2 (baseline trial)"
      sleep "${MEASURE_DURATION//[^0-9]/}" &   # sleep same duration so kill/wait below works
      PID_NOISY=$!
    else
      "$WRK2" -t 2 -c 50 -d "$MEASURE_DURATION" -L \
        -s "$ROOT_DIR/configs/wrk2/noisy-neighbor.lua" \
        "http://127.0.0.1:18081/" -R "$TARGET_NOISY" \
        > "$TRIAL_DIR/noisy-load.txt" 2>&1 &
      PID_NOISY=$!
    fi
    ;;
  burst)
    bash "$ROOT_DIR/scripts/run/run-noisy-burst.sh" \
      "$TRIAL_DIR/noisy-load.txt" "$BURST_DURATION" &
    PID_NOISY=$!
    ;;
  churn)
    bash "$ROOT_DIR/scripts/run/run-noisy-churn.sh" \
      "$TRIAL_DIR/noisy-load.txt" "$CHURN_DURATION" "$CHURN_PAYLOAD_RPS" &
    PID_NOISY=$!
    ;;
  *)
    fail "Unknown mode: $NOISY_MODE"
    ;;
esac

# Wait for all wrk2 instances to finish
wait $PID_COMPOSE || warn "compose-post wrk2 exited non-zero"
wait $PID_HOME    || warn "home-timeline wrk2 exited non-zero"
wait $PID_USER    || warn "user-timeline wrk2 exited non-zero"
kill $PID_NOISY 2>/dev/null || true; wait $PID_NOISY 2>/dev/null || true

RUN_END=$(date +"%Y-%m-%d %H:%M:%S")
tick "Measurement complete"

# ─── Stop metrics ────────────────────────────────────────────────────────────
kill $PID_TOP 2>/dev/null || true; wait $PID_TOP 2>/dev/null || true

# ─── System snapshots ─────────────────────────────────────────────────────────
log "Collecting system snapshots (with retries)..."

_kubectl_top_retry() {
  local desc="$1"; local out="$2"; shift 2
  local cmd=("$@")
  for attempt in 1 2 3; do
    if "${cmd[@]}" > "$out" 2>/dev/null && [[ -s "$out" ]]; then
      tick "$desc → $(wc -l < "$out") lines"
      return 0
    fi
    warn "$desc attempt ${attempt}/3 returned empty — retrying in 5s..."
    sleep 5
  done
  warn "$desc failed after 3 attempts — file will be empty"
  : > "$out"
}

_kubectl_top_retry "pod-cpu (dsb-exp)"       "$TRIAL_DIR/pod-cpu.txt"             kubectl top pod -n "$NAMESPACE"
_kubectl_top_retry "ztunnel-kubectl-top"     "$TRIAL_DIR/ztunnel-kubectl-top.txt" kubectl top pod -n istio-system
_kubectl_top_retry "node-cpu"                "$TRIAL_DIR/node-cpu.txt"            kubectl top node
kubectl get pods -n "$NAMESPACE" -o wide > "$TRIAL_DIR/pod-placement.txt" 2>/dev/null || true

# ─── Jaeger trace collection (10% sampling for noisy trials) ─────────────────
if [[ "$JAEGER_READY" == "true" ]]; then
  log "Collecting Jaeger traces (10% sampling)..."
  bash "$ROOT_DIR/scripts/metrics/collect-traces.sh" \
    "127.0.0.1" "$TRIAL_DIR/jaeger-traces.json" || warn "Jaeger collection failed"
fi

# ─── Metadata ─────────────────────────────────────────────────────────────────
{
  echo "Experiment: 13"
  echo "Trial: trial_${TRIAL_NUM}"
  echo "Run ID: $RUN_ID"
  echo "Victim Case: ${VICTIM_CASE}"
  echo "Noisy Mode: ${NOISY_MODE}"
  echo "Noisy RPS: ${NOISY_RPS:-varies}"
  echo "Start: $RUN_START"
  echo "End: $RUN_END"
  echo "DSB Rates: compose=${COMPOSE_RPS} home=${HOME_RPS} user=${USER_RPS}"
  echo "Worker-0: $WORKER_0"
  echo "ztunnel pod: $ZTUNNEL_POD"
  echo "Config hash: $(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
} > "$TRIAL_DIR/run-metadata.txt"

log "Trial complete → $TRIAL_DIR"
echo ""
echo "========== TRIAL SUMMARY =========="
echo "Case:  ${VICTIM_CASE}  | Mode: ${NOISY_MODE}"
echo "Trial: trial_${TRIAL_NUM}"
echo "Dir:   $TRIAL_DIR"
echo "==================================="
