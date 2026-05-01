#!/bin/bash
# Experiment 11 — Master experiment runner: one full repetition.
# Plain Kubernetes — NO Istio / ztunnel.
# Collects wrk2 latency percentiles for all 3 DSB endpoints + system snapshots.
# Deliberately does NOT collect ztunnel metrics (there are none).
# Jaeger traces are collected when Jaeger is available (DSB native tracing, no mTLS).
#
# Usage: ./run-experiment.sh
# Output: data/raw/run_NNN/

set -euo pipefail

# Allow running as root (sudo) — use appu's kubeconfig if root's is absent
if [[ ! -f "${KUBECONFIG:-$HOME/.kube/config}" ]] && [[ -f /home/appu/.kube/config ]]; then
  export KUBECONFIG=/home/appu/.kube/config
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="dsb-exp11"
NAMESPACE_OBS="observability"

RAW_DIR="$ROOT_DIR/data/raw"
mkdir -p "$RAW_DIR"

# Determine run number
RUN_NUM=$(printf "%03d" $(( $(ls -d "$RAW_DIR"/run_* 2>/dev/null | wc -l) + 1 )))
PHASE_DIR="$RAW_DIR/run_${RUN_NUM}"
mkdir -p "$PHASE_DIR"

RUN_ID=$(date +"%Y%m%d_%H%M%S")
TIMELINE_FILE="$RAW_DIR/experiment_timeline.txt"

# Load rates from config
source "$ROOT_DIR/configs/wrk2/rates.env"

WRK2="${WRK2:-$(command -v wrk2)}"

# ==============================
# HELPERS
# ==============================
log()       { echo -e "\n[INFO] $1"; }
warn()      { echo -e "\n[WARN] $1"; }
fail()      { echo -e "\n[ERROR] $1"; exit 1; }
tick()      { echo -e "\n\033[1;32m✔ $1\033[0m"; }
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
log "Mode: plain Kubernetes (NO Istio / ztunnel)"

kubectl cluster-info > /dev/null || fail "kubectl not connected"
[[ -x "$WRK2" ]] || fail "wrk2 binary not found at $WRK2 — set WRK2= env var or symlink"

# ---- Port-forward to nginx-thrift ----
log "Starting port-forward to nginx-thrift on localhost:18080..."
pkill -f "kubectl port-forward svc/nginx-thrift 18080:8080" || true
kubectl port-forward svc/nginx-thrift 18080:8080 -n "$NAMESPACE" &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT
sleep 3
tick "Port-forward ready (localhost:18080)"

NGINX_IP="127.0.0.1"

# ---- Verify victim-tier pods are on worker-0 ----
log "Verifying victim-tier pods on worker-0..."
SOCIAL_GRAPH_NODE=$(kubectl get pod -n "$NAMESPACE" -l service=social-graph-service \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "")
WORKER_0="default-pool-ssp-11b2c93c3e14"
if [[ "$SOCIAL_GRAPH_NODE" != "$WORKER_0" ]]; then
  warn "social-graph-service pod not confirmed on worker-0 (found: ${SOCIAL_GRAPH_NODE:-unknown})"
fi

# ---- Confirm NO Istio/ztunnel ----
if kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels}' 2>/dev/null \
    | grep -q "istio.io/dataplane-mode"; then
  warn "Namespace $NAMESPACE has Istio ambient label — this SHOULD be a plain K8s experiment!"
fi

# ---- Jaeger port-forward ----
JAEGER_IP=""
if kubectl get svc jaeger-query -n "$NAMESPACE_OBS" > /dev/null 2>&1; then
  log "Starting Jaeger port-forward on localhost:16686..."
  pkill -f "kubectl port-forward svc/jaeger-query 16686:16686" || true
  sleep 1
  kubectl port-forward svc/jaeger-query 16686:16686 -n "$NAMESPACE_OBS" &
  JAEGER_PF_PID=$!
  trap "kill $PF_PID $JAEGER_PF_PID 2>/dev/null || true" EXIT

  JAEGER_READY=false
  for i in $(seq 1 15); do
    if curl -s --connect-timeout 2 "http://127.0.0.1:16686/api/services" > /dev/null 2>&1; then
      JAEGER_READY=true
      break
    fi
    if ! kill -0 "$JAEGER_PF_PID" 2>/dev/null; then
      warn "Jaeger port-forward process died"
      break
    fi
    sleep 2
  done

  if [[ "$JAEGER_READY" == "true" ]]; then
    JAEGER_IP="127.0.0.1"
    tick "Jaeger port-forward ready (localhost:16686)"
  else
    warn "Jaeger port-forward started but not responding — traces will be skipped"
  fi
else
  warn "Jaeger service not found in $NAMESPACE_OBS — traces will not be collected"
fi

# ==============================
# BACKGROUND METRICS
# NOTE: No ztunnel poller — this is a plain K8s experiment.
# We collect node + pod CPU snapshots only.
# ==============================
log "Background metrics: no ztunnel poller (plain K8s). Node/pod CPU collected at end."

# ==============================
# NOTE: Warmup is done ONCE at the start by run_sequential_experiments.sh
# (not per-rep — cluster stays warm across all reps via 90s cooldowns)
# ==============================

# ==============================
# MEASUREMENT RUN (180s × 3 endpoints in parallel)
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
# SYSTEM SNAPSHOTS
# ==============================
log "Collecting system snapshots..."
kubectl top pod -n "$NAMESPACE" > "$PHASE_DIR/pod-cpu.txt"   2>/dev/null || true
kubectl top node               > "$PHASE_DIR/node-cpu.txt"   2>/dev/null || true
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
  echo "Experiment: 11"
  echo "Run: run_${RUN_NUM}"
  echo "Run ID: $RUN_ID"
  echo "Start: $RUN_START"
  echo "End: $RUN_END"
  echo "Duration: $MEASURE_DURATION"
  echo "Warmup: $WARMUP_DURATION"
  echo "Service mesh: NONE (plain Kubernetes)"
  echo "Endpoints:"
  echo "  compose-post    → ${COMPOSE_RPS} RPS"
  echo "  home-timeline   → ${HOME_RPS} RPS"
  echo "  user-timeline   → ${USER_RPS} RPS"
  echo "Worker-0: $WORKER_0"
  echo "ztunnel pod: N/A (no Istio)"
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
echo "Mesh:     NONE (plain K8s)"
echo "Duration: $MEASURE_DURATION"
echo "Endpoints:"
echo "  compose-post    → ${COMPOSE_RPS} RPS → $PHASE_DIR/compose-post.txt"
echo "  home-timeline   → ${HOME_RPS} RPS → $PHASE_DIR/home-timeline.txt"
echo "  user-timeline   → ${USER_RPS} RPS → $PHASE_DIR/user-timeline.txt"
echo "=================================="
