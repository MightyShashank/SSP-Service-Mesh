#!/bin/bash
# Sync experiment results from worker nodes to local machine.
# Useful when metrics are captured directly on worker nodes via SSH.
#
# Usage: bash sync-logs.sh <run_dir>

set -euo pipefail

RUN_DIR="${1:-}"
[[ -n "$RUN_DIR" ]] || { echo "Usage: $0 <run_dir>"; exit 1; }

log() { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }

log "Syncing logs to $RUN_DIR..."

# Sync kubectl logs for DSB pods
log "Collecting DSB pod logs..."
NAMESPACE="dsb-exp"
mkdir -p "$RUN_DIR/pod-logs"

for POD in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  kubectl logs -n "$NAMESPACE" "$POD" --tail=500 \
    > "$RUN_DIR/pod-logs/${POD}.log" 2>/dev/null || true
done

# Sync ztunnel logs
log "Collecting ztunnel logs..."
for POD in $(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  kubectl logs -n istio-system "$POD" --tail=1000 \
    > "$RUN_DIR/pod-logs/ztunnel-${POD}.log" 2>/dev/null || true
done

log "Log sync complete → $RUN_DIR/pod-logs/"
