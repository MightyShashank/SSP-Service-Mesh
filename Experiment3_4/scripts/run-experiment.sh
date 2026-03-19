# This is a full pipeline automation
#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="mesh-exp"

RESULTS_DIR="../results/raw"
RUN_ID=$(date +"%Y%m%d_%H%M%S")

TRAFFIC_DIR="../traffic"

# Create structured output dirs
BASELINE_DIR="$RESULTS_DIR/$RUN_ID/baseline"
INTERFERENCE_DIR="$RESULTS_DIR/$RUN_ID/interference"
LOAD_RAMP_DIR="$RESULTS_DIR/$RUN_ID/load-ramp"
SYSTEM_DIR="$RESULTS_DIR/$RUN_ID/system"

mkdir -p "$BASELINE_DIR" "$INTERFERENCE_DIR" "$LOAD_RAMP_DIR" "$SYSTEM_DIR"

export RUN_ID

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

log "Verifying Fortio availability..."

kubectl exec -n "$NAMESPACE" client -- fortio version > /dev/null 2>&1 \
  || fail "Fortio not available inside client pod"

echo "✔ Client + Fortio ready"

# ==============================
# STEP 0.5 — WARMUP
# ==============================
log "Running system warmup..."

bash "$TRAFFIC_DIR/warmup.sh"

echo "✔ Warmup completed"

# ==============================
# STEP 1 — BASELINE
# ==============================
log "Running BASELINE experiment..."

kubectl exec -n "$NAMESPACE" client -- \
  fortio load -c 50 -qps 500 -t 120s -loglevel Error \
  -json - \
  http://svc-a.mesh-exp \
  > "$BASELINE_DIR/baseline.json" \
  || fail "Baseline run failed"

echo "✔ Baseline completed → $BASELINE_DIR/baseline.json"

# ==============================
# STEP 2 — INTERFERENCE
# ==============================
log "Running INTERFERENCE experiment..."

# svc-a
kubectl exec -n "$NAMESPACE" client -- \
  fortio load -c 50 -qps 500 -t 300s -loglevel Error \
  -json - \
  http://svc-a.mesh-exp \
  > "$INTERFERENCE_DIR/svc-a.json" &

PID_A=$!

# svc-b
kubectl exec -n "$NAMESPACE" client -- \
  fortio load -c 200 -qps 2000 -t 300s -loglevel Error \
  -json - \
  http://svc-b.mesh-exp \
  > "$INTERFERENCE_DIR/svc-b.json" &

PID_B=$!

wait $PID_A || fail "svc-a interference failed"
wait $PID_B || fail "svc-b interference failed"

echo "✔ Interference completed → $INTERFERENCE_DIR"

# ==============================
# STEP 3 — LOAD RAMP
# ==============================
log "Running LOAD RAMP experiment..."

loads=(500 1000 2000 4000)

for qps in "${loads[@]}"
do
  echo "[Load Ramp] svc-b at $qps QPS"

  # svc-a constant
  kubectl exec -n "$NAMESPACE" client -- \
    fortio load -c 50 -qps 500 -t 120s -loglevel Error \
    -json - \
    http://svc-a.mesh-exp \
    > "$LOAD_RAMP_DIR/svc-a_$qps.json" &

  PID_A=$!

  # svc-b ramp
  kubectl exec -n "$NAMESPACE" client -- \
    fortio load -c 200 -qps $qps -t 120s -loglevel Error \
    -json - \
    http://svc-b.mesh-exp \
    > "$LOAD_RAMP_DIR/svc-b_$qps.json" &

  PID_B=$!

  wait $PID_A || fail "svc-a failed at $qps"
  wait $PID_B || fail "svc-b failed at $qps"

  echo "✔ Completed load level: $qps"
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
echo "Tool: Fortio (QPS-controlled)"
echo "================================\n"