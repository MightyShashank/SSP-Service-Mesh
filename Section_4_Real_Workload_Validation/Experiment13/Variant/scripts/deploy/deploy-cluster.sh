#!/bin/bash
# Verify cluster connectivity and label nodes.
# For managed clusters: no cluster creation needed — just verify and label.
#
# Usage: bash deploy-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

log()  { echo -e "\n[INFO] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

# ---- Verify cluster connectivity ----
log "Verifying cluster connectivity..."
kubectl cluster-info > /dev/null || fail "kubectl not connected to cluster"
tick "Cluster reachable"

# ---- Verify node count ----
log "Checking node count..."
NODE_COUNT=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
if [[ "$NODE_COUNT" -lt 3 ]]; then
  fail "Expected at least 3 Ready nodes, found $NODE_COUNT"
fi
tick "$NODE_COUNT nodes Ready"

# ---- Print node info ----
log "Node details:"
kubectl get nodes -o wide

# ---- Label nodes ----
log "Labeling nodes for deterministic scheduling..."
bash "$ROOT_DIR/configs/kubernetes/node-labels.sh"
tick "Nodes labeled"

# ---- Collect hardware info ----
log "Collecting hardware info..."
mkdir -p "$ROOT_DIR/data/metadata"
{
  echo "=== Node Info ==="
  kubectl get nodes -o wide
  echo ""
  echo "=== Kubernetes Version ==="
  kubectl version --short 2>/dev/null || kubectl version
} > "$ROOT_DIR/data/metadata/hardware-info.txt"
tick "Hardware info saved to data/metadata/hardware-info.txt"

log "Cluster setup COMPLETE ✅"
