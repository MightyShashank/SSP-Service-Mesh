#!/bin/bash
# Capture kubectl top snapshots (pod + node CPU).
# Run once at the end of a measurement window.
#
# Usage: bash capture-k8s-stats.sh <output_dir>

set -euo pipefail

OUTPUT_DIR="${1:-/tmp/k8s-stats}"
mkdir -p "$OUTPUT_DIR"

log() { echo -e "\n[INFO] $1"; }

log "Collecting kubectl top snapshots..."

kubectl top pod -n dsb-exp          > "$OUTPUT_DIR/pod-cpu-dsb.txt"       2>/dev/null || true
kubectl top pod -n istio-system     > "$OUTPUT_DIR/pod-cpu-istio.txt"     2>/dev/null || true
kubectl top pod -n observability    > "$OUTPUT_DIR/pod-cpu-obs.txt"       2>/dev/null || true
kubectl top node                    > "$OUTPUT_DIR/node-cpu.txt"           2>/dev/null || true
kubectl get pods -n dsb-exp -o wide > "$OUTPUT_DIR/pod-placement.txt"     2>/dev/null || true

log "kubectl top snapshots saved to $OUTPUT_DIR"
