#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="mesh-exp"
WORKER_NODE="ssp-worker-1"

RESULTS_DIR="../results/raw"
RUN_ID=$(date +"%Y%m%d_%H%M%S")

TRAFFIC_DIR="../traffic"
EBPF_DIR="../ebpf"

# Load levels per experiment spec: svc-B ∈ {0, 100, 500, 1000} RPS
LOAD_LEVELS=(0 100 500 1000)

# svc-A is always fixed at 100 RPS
SVC_A_QPS=100
DURATION="120s"

TIMELINE_FILE="$RESULTS_DIR/experiment_timeline.txt"

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

  # Try to wait until node CPU < 50% (requires Metrics Server)
  # If Metrics Server is not available, skip CPU check and just use the fixed wait
  if ! kubectl top node > /dev/null 2>&1; then
    log "Metrics API not available — using fixed 60s cooldown only"
    tick "Cooldown completed (fixed wait)"
    return
  fi

  for i in {1..20}; do
    CPU=$(kubectl top node 2>/dev/null | awk 'NR==2 {print $3}' | sed 's/%//' || echo "")

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
# DISCOVER ZTUNNEL PID ON WORKER NODE
# ==============================
log "Discovering ztunnel PID on $WORKER_NODE..."

# Use pgrep directly on the worker node to find the main ztunnel process
# -f → match full command line
# -o → pick the oldest process (main ztunnel process)
ZTUNNEL_PID=$(ssh "$WORKER_NODE" "sudo pgrep -fo ztunnel" 2>/dev/null || echo "")

# If not found, print debug info
if [ -z "${ZTUNNEL_PID:-}" ]; then
  echo ""
  echo "DEBUG: Listing ztunnel-related processes on $WORKER_NODE:"
  ssh "$WORKER_NODE" "sudo ps aux | grep -i ztunnel | grep -v grep" 2>/dev/null || true
  echo ""
  fail "Cannot find ztunnel process on $WORKER_NODE. Check output above."
fi

tick "ztunnel PID → $ZTUNNEL_PID"

# ==============================
# CHECK ZTUNNEL SYMBOL AVAILABILITY
# ==============================
log "Checking ztunnel binary for debug symbols..."

SYMBOL_COUNT=$(ssh "$WORKER_NODE" "sudo nm /proc/$ZTUNNEL_PID/exe 2>/dev/null | wc -l" 2>/dev/null || echo "0")

if [ "$SYMBOL_COUNT" -gt 100 ]; then
  PROBE_MODE="full"
  log "ztunnel has symbols ($SYMBOL_COUNT) → full uprobe mode"
else
  PROBE_MODE="kprobe"
  log "ztunnel binary stripped → using kprobe-only fallback"
fi

# ==============================
# COPY EBPF PROBES TO WORKER NODE
# ==============================
log "Copying eBPF probes to $WORKER_NODE..."

ssh "$WORKER_NODE" "mkdir -p /tmp/ebpf-exp4"
scp "$EBPF_DIR/latency_decomp.bt" "$WORKER_NODE:/tmp/ebpf-exp4/"
scp "$EBPF_DIR/sched_occupancy.bt" "$WORKER_NODE:/tmp/ebpf-exp4/"
scp "$EBPF_DIR/queue_delay.bt" "$WORKER_NODE:/tmp/ebpf-exp4/"

tick "eBPF probes copied to worker node"

# ==============================
# WARMUP
# ==============================
log "Warmup..."
bash "$TRAFFIC_DIR/warmup.sh"
tick "Warmup completed"

# ==============================
# MAIN EXPERIMENT LOOP
# For each load level: start eBPF → start traffic → wait → stop eBPF
# ==============================
declare -A LOAD_START_TIMES
declare -A LOAD_END_TIMES

for LOAD in "${LOAD_LEVELS[@]}"
do
  echo ""
  echo "============================================"
  echo "[PHASE] svc-B Load = $LOAD RPS"
  echo "============================================"

  PHASE_DIR="$RESULTS_DIR/$RUN_ID/load-$LOAD"
  mkdir -p "$PHASE_DIR"

  LOAD_START_TIMES[$LOAD]=$(timestamp)

  # ----------------------------------
  # START EBPF PROBES (background)
  # ----------------------------------
  log "Starting eBPF probes on $WORKER_NODE..."

  # Latency decomposition probe
  ssh "$WORKER_NODE" "sudo bpftrace /tmp/ebpf-exp4/latency_decomp.bt $ZTUNNEL_PID" \
    > "$PHASE_DIR/latency_decomp.log" 2>&1 &
  PID_EBPF_LATENCY=$!

  # Scheduler occupancy probe
  ssh "$WORKER_NODE" "sudo bpftrace /tmp/ebpf-exp4/sched_occupancy.bt" \
    > "$PHASE_DIR/sched_occupancy.log" 2>&1 &
  PID_EBPF_SCHED=$!

  # Queue delay probe
  ssh "$WORKER_NODE" "sudo bpftrace /tmp/ebpf-exp4/queue_delay.bt" \
    > "$PHASE_DIR/queue_delay.log" 2>&1 &
  PID_EBPF_QUEUE=$!

  # Let probes attach
  sleep 3

  tick "eBPF probes running"

  # ----------------------------------
  # RUN FORTIO TRAFFIC
  # ----------------------------------
  log "Starting traffic: svc-A=${SVC_A_QPS} QPS, svc-B=${LOAD} QPS, duration=${DURATION}"

  bash "$TRAFFIC_DIR/load-generator.sh" "$SVC_A_QPS" "$LOAD" "$DURATION" "$PHASE_DIR"

  tick "Traffic completed for load=$LOAD"

  # ----------------------------------
  # STOP EBPF PROBES
  # Send SIGINT for graceful shutdown (triggers END block)
  # ----------------------------------
  log "Stopping eBPF probes..."

  # Send SIGINT to the SSH sessions (which forwards to bpftrace)
  kill -INT $PID_EBPF_LATENCY 2>/dev/null || true
  kill -INT $PID_EBPF_SCHED 2>/dev/null || true
  kill -INT $PID_EBPF_QUEUE 2>/dev/null || true

  # Wait for graceful shutdown
  wait $PID_EBPF_LATENCY 2>/dev/null || true
  wait $PID_EBPF_SCHED 2>/dev/null || true
  wait $PID_EBPF_QUEUE 2>/dev/null || true

  # Also kill on remote just in case
  ssh "$WORKER_NODE" "sudo pkill -INT -f bpftrace" > /dev/null 2>&1 || true
  sleep 2

  tick "eBPF probes stopped"

  LOAD_END_TIMES[$LOAD]=$(timestamp)

  tick "Phase load=$LOAD completed"

  # COOLDOWN BETWEEN PHASES
  cooldown
done

tick "All load levels completed"

# ==============================
# SYSTEM METRICS
# ==============================
log "Collecting system metrics..."

SYSTEM_DIR="$RESULTS_DIR/$RUN_ID/system"
mkdir -p "$SYSTEM_DIR"

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
  echo "Probe mode: $PROBE_MODE"
  echo "ztunnel PID: $ZTUNNEL_PID"
  echo ""

  idx=1
  for LOAD in "${LOAD_LEVELS[@]}"
  do
    echo "$idx. svc-B=${LOAD} RPS:"
    echo "Start=${LOAD_START_TIMES[$LOAD]}"
    echo "End=${LOAD_END_TIMES[$LOAD]}"
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
echo "Probe Mode: $PROBE_MODE"
echo "Load Levels: ${LOAD_LEVELS[*]}"
echo "ztunnel PID: $ZTUNNEL_PID"
echo "Timeline File: $TIMELINE_FILE"
echo "Results: $RESULTS_DIR/$RUN_ID/"
echo "================================\n"
