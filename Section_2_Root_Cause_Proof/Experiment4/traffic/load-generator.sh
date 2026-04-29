# Parameterized load generator for Experiment 4
# Usage: ./load-generator.sh <svc_a_qps> <svc_b_qps> <duration> <output_dir>
#
# svc-A: Fixed rate (VIP/latency-sensitive)
# svc-B: Variable rate (noisy neighbor)
# When svc_b_qps=0, only svc-A traffic is generated (baseline)

#!/bin/bash

set -euo pipefail

# ==============================
# ARGUMENTS
# ==============================
if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <svc_a_qps> <svc_b_qps> <duration> <output_dir>"
  echo "Example: $0 100 500 120s /path/to/output"
  exit 1
fi

SVC_A_QPS=$1
SVC_B_QPS=$2
DURATION=$3
OUTPUT_DIR=$4

NAMESPACE="mesh-exp"
SVC_A_CONNS=10
SVC_B_CONNS=100

mkdir -p "$OUTPUT_DIR"

echo "[Load Generator] svc-A=${SVC_A_QPS} QPS | svc-B=${SVC_B_QPS} QPS | duration=${DURATION}"

# ==============================
# SVC-A (always runs)
# ==============================
echo "[Load Generator] Starting svc-A traffic (${SVC_A_QPS} QPS)..."

kubectl exec -n "$NAMESPACE" client -- \
  fortio load -c "$SVC_A_CONNS" -qps "$SVC_A_QPS" -t "$DURATION" -loglevel Error \
  -json - \
  http://svc-a.mesh-exp \
  > "$OUTPUT_DIR/svc-a.json" &

PID_A=$!

# ==============================
# SVC-B (only if QPS > 0)
# ==============================
if [ "$SVC_B_QPS" -gt 0 ]; then
  echo "[Load Generator] Starting svc-B traffic (${SVC_B_QPS} QPS)..."

  kubectl exec -n "$NAMESPACE" client -- \
    fortio load -c "$SVC_B_CONNS" -qps "$SVC_B_QPS" -t "$DURATION" -loglevel Error \
    -json - \
    http://svc-b.mesh-exp \
    > "$OUTPUT_DIR/svc-b.json" &

  PID_B=$!
else
  echo "[Load Generator] svc-B QPS=0 → baseline mode (no noisy neighbor)"
  PID_B=""
fi

# ==============================
# WAIT FOR COMPLETION
# ==============================
wait $PID_A || { echo "[ERROR] svc-A load generation failed"; exit 1; }

if [ -n "$PID_B" ]; then
  wait $PID_B || { echo "[ERROR] svc-B load generation failed"; exit 1; }
fi

echo "[Load Generator] Completed — results in $OUTPUT_DIR"
