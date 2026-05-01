#!/bin/bash
# Master experiment runner for Experiment 12 — single repetition.
# Runs: warmup (60s) → measure (180s) × 3 endpoints in parallel
#        + background ztunnel CPU/RSS polling
#        + Jaeger trace collection at end
#
# Usage: ./run-experiment.sh
# Output: data/raw/run_NNN/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="dsb-exp"
NAMESPACE_OBS="observability"
WORKER_0="default-pool-ssp-11b2c93c3e14"

RAW_DIR="$ROOT_DIR/data/raw"
mkdir -p "$RAW_DIR"

# Determine run number (run_001, run_002, ...)
RUN_NUM=$(printf "%03d" $(( $(ls -d "$RAW_DIR"/run_* 2>/dev/null | wc -l) + 1 )))
PHASE_DIR="$RAW_DIR/run_${RUN_NUM}"
mkdir -p "$PHASE_DIR"

RUN_ID=$(date +"%Y%m%d_%H%M%S")
TIMELINE_FILE="$RAW_DIR/experiment_timeline.txt"

# Load rates from config
source "$ROOT_DIR/configs/wrk2/rates.env"
# COMPOSE_RPS, HOME_RPS, USER_RPS, WRK2_THREADS, WRK2_CONNS, WRK2_DIST
# WARMUP_DURATION, MEASURE_DURATION

WRK2="${WRK2:-$(command -v wrk2)}"

# ==============================
# HELPERS
# ==============================
log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

cooldown() {
  log "Cooling down system (60s min + CPU check)..."
  sleep 60
  if ! kubectl top node > /dev/null 2>&1; then
    log "Metrics API not available — using fixed 60s cooldown"
    return
  fi
  for i in {1..20}; do
    CPU=$(kubectl top node 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $3}' || echo "")
    if [[ -z "$CPU" ]]; then sleep 5; continue; fi
    if [ "$CPU" -lt 40 ]; then tick "System stabilized (CPU < 40%)"; return; fi
    log "Waiting... CPU=${CPU}%"
    sleep 10
  done
  log "Cooldown timeout reached, continuing..."
}

# ==============================
# PRE-CHECKS
# ==============================
log "Run $RUN_NUM ($RUN_ID) starting → $PHASE_DIR"

kubectl cluster-info > /dev/null || fail "kubectl not connected"

[[ -x "$WRK2" ]] || fail "wrk2 binary not found at $WRK2 — set WRK2= env var or symlink"

log "Ensuring port-forward is running on localhost:18080..."
pkill -f "kubectl port-forward svc/nginx-thrift 18080:8080" || true
kubectl port-forward svc/nginx-thrift 18080:8080 -n "$NAMESPACE" &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT
sleep 3
tick "Port-forward ready"

# All wrk2 traffic goes via port-forward on localhost
NGINX_IP="127.0.0.1"

log "Verifying victim-tier pods on worker-0..."
SOCIAL_GRAPH_NODE=$(kubectl get pod -n "$NAMESPACE" -l service=social-graph-service \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || \
  kubectl get pod -n "$NAMESPACE" -l app=social-graph-service \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "")
if [[ "$SOCIAL_GRAPH_NODE" != "$WORKER_0" ]]; then
  warn "social-graph pod not confirmed on worker-0 (found: ${SOCIAL_GRAPH_NODE:-unknown — label may differ})"
fi

log "Finding ztunnel pod on worker-0..."
ZTUNNEL_POD=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$WORKER_0" '$0 ~ "ztunnel" && $7 == node {print $1}')
[[ -n "$ZTUNNEL_POD" ]] || fail "No ztunnel pod on worker-0"
tick "ztunnel pod → $ZTUNNEL_POD"

# Getting ztunnel PID (inside the pod, process 1 is ztunnel)
ZTUNNEL_PID=$(kubectl exec -n istio-system "$ZTUNNEL_POD" -- \
  sh -c 'cat /proc/1/status 2>/dev/null | grep "^Pid:" | awk "{print \$2}"' 2>/dev/null || echo "")
if [[ -z "$ZTUNNEL_PID" ]]; then
  warn "Could not get ztunnel PID — CPU/RSS metrics will be skipped"
fi

# Jaeger: start a port-forward on localhost:16686 so collect-traces.sh can reach it
JAEGER_IP=""
if kubectl get svc jaeger-query -n "$NAMESPACE_OBS" > /dev/null 2>&1; then
  log "Starting Jaeger port-forward on localhost:16686..."
  pkill -f "kubectl port-forward svc/jaeger-query 16686:16686" || true
  sleep 1
  # Start port-forward — show output so errors are visible
  kubectl port-forward svc/jaeger-query 16686:16686 -n "$NAMESPACE_OBS" &
  JAEGER_PF_PID=$!
  trap "kill $PF_PID $JAEGER_PF_PID 2>/dev/null || true" EXIT

  # Wait until localhost:16686 actually responds (up to 30s)
  JAEGER_READY=false
  for i in $(seq 1 15); do
    if curl -s --connect-timeout 2 "http://127.0.0.1:16686/api/services" > /dev/null 2>&1; then
      JAEGER_READY=true
      break
    fi
    if ! kill -0 "$JAEGER_PF_PID" 2>/dev/null; then
      warn "Jaeger port-forward process died — traces will not be collected"
      break
    fi
    sleep 2
  done

  if [[ "$JAEGER_READY" == "true" ]]; then
    JAEGER_IP="127.0.0.1"
    tick "Jaeger port-forward ready (localhost:16686)"
  else
    warn "Jaeger port-forward started but localhost:16686 not responding — traces will be skipped"
  fi
else
  warn "Jaeger service not found in $NAMESPACE_OBS — traces will not be collected"
fi

# ==============================
# START BACKGROUND METRICS
# ==============================
log "Starting background metrics collection..."

# Always: poll ztunnel CPU via kubectl top every 5s (works without PID)
bash "$ROOT_DIR/scripts/metrics/capture-ztunnel-cpu-top.sh" \
  "$PHASE_DIR/ztunnel-top.txt" 5 &
PID_TOP=$!
tick "ztunnel kubectl-top poller started → $PHASE_DIR/ztunnel-top.txt"

# Optional: per-thread /proc stats if PID is known
if [[ -n "$ZTUNNEL_PID" ]]; then
  bash "$ROOT_DIR/scripts/metrics/capture-ztunnel-stats.sh" \
    "$ZTUNNEL_POD" "$ZTUNNEL_PID" "$PHASE_DIR/ztunnel-cpu.txt" &
  PID_CPU=$!

  bash "$ROOT_DIR/scripts/metrics/capture-ztunnel-rss.sh" \
    "$ZTUNNEL_POD" "$ZTUNNEL_PID" "$PHASE_DIR/ztunnel-rss.txt" &
  PID_RSS=$!
  tick "ztunnel per-thread CPU + RSS pollers started"
else
  PID_CPU=""
  PID_RSS=""
  warn "Skipping per-thread CPU/RSS polling (PID unknown) — kubectl-top still active"
fi

# ==============================
# NOTE: Warmup is done ONCE at the start by run_sequential_experiments.sh
# (not per-rep — cluster stays warm across all reps via 90s cooldowns)
# ==============================

# ==============================
# MEASUREMENT RUN (180s × 3 endpoints)
# ==============================
RUN_START=$(timestamp)
log "Starting measurement run (${MEASURE_DURATION}) — 3 endpoints in parallel..."

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L -T 10s \
  -s "$ROOT_DIR/configs/wrk2/compose-post.lua" \
  "http://127.0.0.1:18080/wrk2-api/post/compose" -R "$COMPOSE_RPS" \
  > "$PHASE_DIR/compose-post.txt" 2>&1 &
PID_COMPOSE=$!

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L -T 10s \
  -s "$ROOT_DIR/configs/wrk2/read-home-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/home-timeline/read" -R "$HOME_RPS" \
  > "$PHASE_DIR/home-timeline.txt" 2>&1 &
PID_HOME=$!

"$WRK2" -t "$WRK2_THREADS" -c "$WRK2_CONNS" -d "$MEASURE_DURATION" -L -T 10s \
  -s "$ROOT_DIR/configs/wrk2/read-user-timeline.lua" \
  "http://127.0.0.1:18080/wrk2-api/user-timeline/read" -R "$USER_RPS" \
  > "$PHASE_DIR/user-timeline.txt" 2>&1 &
PID_USER=$!

wait $PID_COMPOSE || warn "compose-post wrk2 exited with error"
wait $PID_HOME    || warn "home-timeline wrk2 exited with error"
wait $PID_USER    || warn "user-timeline wrk2 exited with error"

RUN_END=$(timestamp)
tick "Measurement complete (run_${RUN_NUM})"

# ==============================
# STOP BACKGROUND METRICS
# ==============================
kill "$PID_TOP" 2>/dev/null || true; wait "$PID_TOP" 2>/dev/null || true
[[ -n "$PID_CPU" ]] && { kill "$PID_CPU" 2>/dev/null || true; wait "$PID_CPU" 2>/dev/null || true; }
[[ -n "$PID_RSS" ]] && { kill "$PID_RSS" 2>/dev/null || true; wait "$PID_RSS" 2>/dev/null || true; }
tick "Background metrics stopped"

# ==============================
# SYSTEM SNAPSHOTS
# Metrics Server needs 60–120 s after a fresh deploy before kubectl top
# returns data. Retry up to 3 times with a 10 s wait between attempts.
# ==============================
log "Collecting system snapshots (with retries for Metrics Server)..."

_kubectl_top_retry() {
  local desc="$1"; local out="$2"; shift 2
  local cmd=("$@")
  for attempt in 1 2 3; do
    if "${cmd[@]}" > "$out" 2>/dev/null && [[ -s "$out" ]]; then
      tick "$desc → $(wc -l < "$out") lines"
      return 0
    fi
    warn "$desc attempt ${attempt}/3 returned empty — waiting 10 s for Metrics Server..."
    sleep 10
  done
  warn "$desc failed after 3 attempts — file will be empty"
  : > "$out"
}

_kubectl_top_retry "pod-cpu (dsb-exp)"     "$PHASE_DIR/pod-cpu.txt"             kubectl top pod -n "$NAMESPACE"
_kubectl_top_retry "ztunnel-kubectl-top"   "$PHASE_DIR/ztunnel-kubectl-top.txt" kubectl top pod -n istio-system
_kubectl_top_retry "node-cpu"              "$PHASE_DIR/node-cpu.txt"            kubectl top node
kubectl get pods -n "$NAMESPACE" -o wide > "$PHASE_DIR/pod-placement.txt" 2>/dev/null || true
tick "System snapshots saved"

# ==============================
# JAEGER TRACE COLLECTION
# ==============================
if [[ -n "$JAEGER_IP" ]]; then
  log "Collecting Jaeger traces..."
  bash "$ROOT_DIR/scripts/metrics/collect-traces.sh" \
    "$JAEGER_IP" "$PHASE_DIR/jaeger-traces.json" || warn "Jaeger collection failed"
fi

# ==============================
# RUN METADATA
# ==============================
{
  echo "Run: run_${RUN_NUM}"
  echo "Run ID: $RUN_ID"
  echo "Start: $RUN_START"
  echo "End: $RUN_END"
  echo "Duration: $MEASURE_DURATION"
  echo "Warmup: $WARMUP_DURATION"
  echo "Endpoints:"
  echo "  compose-post    → ${COMPOSE_RPS} RPS"
  echo "  home-timeline   → ${HOME_RPS} RPS"
  echo "  user-timeline   → ${USER_RPS} RPS"
  echo "Worker-0: $WORKER_0"
  echo "ztunnel pod: $ZTUNNEL_POD"
  echo "ztunnel PID: ${ZTUNNEL_PID:-unknown}"
  echo "Jaeger IP: ${JAEGER_IP:-N/A}"
  echo "Config hash: $(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
} > "$PHASE_DIR/run-metadata.txt"

# Append to timeline
{
  echo ""
  echo "# run_${RUN_NUM} ($RUN_ID)"
  echo "Start: $RUN_START"
  echo "End:   $RUN_END"
  echo "Dir:   $PHASE_DIR"
} >> "$TIMELINE_FILE"

# ==============================
# FINAL SUMMARY
# ==============================
log "Experiment run_${RUN_NUM} COMPLETE ✅"
echo ""
echo "========== RUN SUMMARY =========="
echo "Run:      run_${RUN_NUM}"
echo "Run ID:   $RUN_ID"
echo "Duration: $MEASURE_DURATION"
echo "Endpoints:"
echo "  compose-post    → ${COMPOSE_RPS} RPS → $PHASE_DIR/compose-post.txt"
echo "  home-timeline   → ${HOME_RPS} RPS → $PHASE_DIR/home-timeline.txt"
echo "  user-timeline   → ${USER_RPS} RPS → $PHASE_DIR/user-timeline.txt"
echo "=================================="
