# This is a full pipeline automation

#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="mesh-exp"

TRAFFIC_DIR="../traffic"
OBS_DIR="../observability"
RESULTS_DIR="../results/raw"

RUN_ID=$(date +"%Y%m%d_%H%M%S")

# Create structured output dirs
BASELINE_DIR="$RESULTS_DIR/$RUN_ID/baseline"
INTERFERENCE_DIR="$RESULTS_DIR/$RUN_ID/interference"
LOAD_RAMP_DIR="$RESULTS_DIR/$RUN_ID/load-ramp"
SYSTEM_DIR="$RESULTS_DIR/$RUN_ID/system"

mkdir -p "$BASELINE_DIR" "$INTERFERENCE_DIR" "$LOAD_RAMP_DIR" "$SYSTEM_DIR"

# ==============================
# LOGGING
# ==============================
log() {
  echo -e "\n[INFO] $1"
}

fail() {
  echo -e "\n[ERROR] $1"
  exit 1
}

# ==============================
# STEP 0 — PRE-CHECKS
# ==============================
log "Checking client pod availability..."

kubectl get pod client -n "$NAMESPACE" > /dev/null \
  || fail "Client pod not found. Run deploy script first."

log "Verifying wrk availability inside client..."

if kubectl exec -n "$NAMESPACE" client -- sh -c "which wrk" > /dev/null 2>&1; then
  echo "✔ wrk binary found inside client pod"
else
  fail "wrk not available inside client pod"
fi

echo "✔ wrk is available inside client pod"

echo "✔ Client + wrk ready"

# ==============================
# STEP 1 — BASELINE
# ==============================
log "Running BASELINE experiment..."

kubectl exec -n "$NAMESPACE" client -- \
  wrk -t2 -c50 -d120s --latency http://svc-a.mesh-exp \
  > "$BASELINE_DIR/baseline.txt"

echo "✔ Baseline completed → $BASELINE_DIR/baseline.txt"

# ==============================
# STEP 2 — INTERFERENCE
# ==============================
log "Running INTERFERENCE experiment..."

# svc-a (latency-sensitive)
kubectl exec -n "$NAMESPACE" client -- \
  wrk -t2 -c50 -d300s --latency http://svc-a.mesh-exp \
  > "$INTERFERENCE_DIR/svc-a.txt" &

PID_A=$!

# svc-b (noisy workload)
kubectl exec -n "$NAMESPACE" client -- \
  wrk -t8 -c400 -d300s --latency http://svc-b.mesh-exp \
  > "$INTERFERENCE_DIR/svc-b.txt" &

PID_B=$!

wait $PID_A
wait $PID_B

echo "✔ Interference completed → $INTERFERENCE_DIR"

# ==============================
# STEP 3 — LOAD RAMP
# ==============================
log "Running LOAD RAMP experiment..."

loads=(100 300 600 1000)

for c in "${loads[@]}"
do
  echo "[Load Ramp] Running load level: $c"

  # svc-a (steady baseline)
  kubectl exec -n "$NAMESPACE" client -- \
    wrk -t2 -c50 -d120s --latency http://svc-a.mesh-exp \
    > "$LOAD_RAMP_DIR/svc-a_$c.txt" &

  PID_A=$!

  # svc-b (increasing load)
  kubectl exec -n "$NAMESPACE" client -- \
    wrk -t4 -c$c -d120s --latency http://svc-b.mesh-exp \
    > "$LOAD_RAMP_DIR/svc-b_$c.txt" &

  PID_B=$!

  wait $PID_A
  wait $PID_B

  echo "✔ Completed load level: $c"
done

echo "✔ Load ramp completed → $LOAD_RAMP_DIR"

# ==============================
# STEP 4 — SYSTEM METRICS
# ==============================
log "Collecting system-level metrics..."

kubectl top pod -n istio-system > "$SYSTEM_DIR/ztunnel_cpu.txt" || true
kubectl top node > "$SYSTEM_DIR/node_cpu.txt" || true
kubectl top pod -n mesh-exp > "$SYSTEM_DIR/pod_cpu.txt" || true

echo "✔ System metrics saved → $SYSTEM_DIR"

# ==============================
# STEP 5 — FINAL SUMMARY
# ==============================
log "Experiment COMPLETED ✅"

echo -e "\n========== RUN SUMMARY =========="
echo "Run ID: $RUN_ID"
echo "Baseline:      $BASELINE_DIR"
echo "Interference:  $INTERFERENCE_DIR"
echo "Load Ramp:     $LOAD_RAMP_DIR"
echo "System Metrics:$SYSTEM_DIR"
echo "================================\n"