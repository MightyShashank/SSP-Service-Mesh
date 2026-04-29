#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="mesh-exp"

RESULTS_DIR="../results/raw"
RUN_ID=$(date +"%Y%m%d_%H%M%S")

TRAFFIC_DIR="../traffic"

BASELINE_DIR="$RESULTS_DIR/$RUN_ID/baseline"
INTERFERENCE_DIR="$RESULTS_DIR/$RUN_ID/interference"
LOAD_RAMP_DIR="$RESULTS_DIR/$RUN_ID/load-ramp"
SYSTEM_DIR="$RESULTS_DIR/$RUN_ID/system"

TIMELINE_FILE="$RESULTS_DIR/experiment_timeline.txt"

mkdir -p "$BASELINE_DIR" "$INTERFERENCE_DIR" "$LOAD_RAMP_DIR" "$SYSTEM_DIR"

# ==============================
# HELPERS
# ==============================
log() {
  echo -e "\n[INFO] $1"
}

tick() {
  echo -e "\n\033[1;32m✔ $1\033[0m"
}

fail() {
  echo -e "\n[ERROR] $1"
  exit 1
}

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

# ==============================
# COOLDOWN FUNCTION
# ==============================
cooldown() {
  log "Cooling down system..."

  # Minimum wait
  sleep 60

  # Wait until node CPU < 50%
  for i in {1..20}; do
    CPU=$(kubectl top node | awk 'NR==2 {print $3}' | sed 's/%//')

    if [ -z "$CPU" ]; then
      log "CPU check failed, retrying..."
      sleep 5
      continue
    fi

    if [ "$CPU" -lt 50 ]; then
      tick "System stabilized (CPU < 50%)"
      return
    fi

    log "Waiting... CPU=${CPU}%"
    sleep 10
  done

  log "Cooldown timeout reached, continuing..."
}

# ==============================
# EXPERIMENT NUMBER
# ==============================
if [ ! -f "$TIMELINE_FILE" ]; then
  EXP_ID=1
else
  LAST=$(grep -oP '# Experiment \K[0-9]+' "$TIMELINE_FILE" | tail -1 || echo 0)
  EXP_ID=$((LAST + 1))
fi

# ==============================
# PRE-CHECKS
# ==============================
log "Checking client pod..."

kubectl get pod client -n "$NAMESPACE" > /dev/null \
  || fail "Client pod not found"

kubectl exec -n "$NAMESPACE" client -- fortio version > /dev/null 2>&1 \
  || fail "Fortio missing"

tick "Client + Fortio ready"

# ==============================
# WARMUP
# ==============================
log "Warmup..."
bash "$TRAFFIC_DIR/warmup.sh"
tick "Warmup completed"

# ==============================
# BASELINE
# ==============================
log "Running BASELINE..."

BASELINE_START=$(timestamp)

kubectl exec -n "$NAMESPACE" client -- \
  fortio load -c 50 -qps 500 -t 120s -loglevel Error \
  -json - \
  http://svc-a.mesh-exp \
  > "$BASELINE_DIR/baseline.json" \
  || fail "Baseline failed"

BASELINE_END=$(timestamp)

tick "Baseline done"

# COOLDOWN
cooldown

# ==============================
# INTERFERENCE
# ==============================
log "Running INTERFERENCE..."

INTERF_START=$(timestamp)

kubectl exec -n "$NAMESPACE" client -- \
  fortio load -c 50 -qps 500 -t 300s -loglevel Error \
  -json - \
  http://svc-a.mesh-exp \
  > "$INTERFERENCE_DIR/svc-a.json" &

PID_A=$!

kubectl exec -n "$NAMESPACE" client -- \
  fortio load -c 200 -qps 2000 -t 300s -loglevel Error \
  -json - \
  http://svc-b.mesh-exp \
  > "$INTERFERENCE_DIR/svc-b.json" &

PID_B=$!

wait $PID_A || fail "svc-a failed"
wait $PID_B || fail "svc-b failed"

INTERF_END=$(timestamp)

tick "Interference done"

# COOLDOWN
cooldown

# ==============================
# LOAD RAMP
# ==============================
log "Running LOAD RAMP..."

declare -A LOAD_START_TIMES
declare -A LOAD_END_TIMES

loads=(500 1000 2000 4000)

for qps in "${loads[@]}"
do
  echo "[Load Ramp] $qps QPS"

  LOAD_START_TIMES[$qps]=$(timestamp)

  kubectl exec -n "$NAMESPACE" client -- \
    fortio load -c 50 -qps 500 -t 120s -loglevel Error \
    -json - \
    http://svc-a.mesh-exp \
    > "$LOAD_RAMP_DIR/svc-a_$qps.json" &

  PID_A=$!

  kubectl exec -n "$NAMESPACE" client -- \
    fortio load -c 200 -qps $qps -t 120s -loglevel Error \
    -json - \
    http://svc-b.mesh-exp \
    > "$LOAD_RAMP_DIR/svc-b_$qps.json" &

  PID_B=$!

  wait $PID_A || fail "svc-a failed at $qps"
  wait $PID_B || fail "svc-b failed at $qps"

  LOAD_END_TIMES[$qps]=$(timestamp)

  tick "Load $qps completed"

  # COOLDOWN AFTER EACH STEP
  cooldown
done

tick "Load ramp done"

# ==============================
# SYSTEM METRICS
# ==============================
log "Collecting system metrics..."

kubectl top pod -n istio-system > "$SYSTEM_DIR/ztunnel_cpu.txt" || true
kubectl top node > "$SYSTEM_DIR/node_cpu.txt" || true
kubectl top pod -n mesh-exp > "$SYSTEM_DIR/pod_cpu.txt" || true

tick "System metrics saved"

# ==============================
# WRITE TIMELINE
# ==============================
{
  echo ""
  echo "# Experiment $EXP_ID ($RUN_ID):"
  echo ""
  echo "1. Baseline:"
  echo "Start=$BASELINE_START"
  echo "End=$BASELINE_END"
  echo ""
  echo "2. Interference:"
  echo "Start=$INTERF_START"
  echo "End=$INTERF_END"
  echo ""
  echo "3. Load-Ramp:"
  echo ""

  idx=1
  for qps in "${loads[@]}"
  do
    echo "3.$idx $qps:"
    echo "Start=${LOAD_START_TIMES[$qps]}"
    echo "End=${LOAD_END_TIMES[$qps]}"
    echo ""
    ((idx++))
  done

} >> "$TIMELINE_FILE"

# ==============================
# SUMMARY
# ==============================
log "Experiment COMPLETED ✅"

echo -e "\n========== RUN SUMMARY =========="
echo "Run ID: $RUN_ID"
echo "Timeline File: $TIMELINE_FILE"
echo "================================\n"