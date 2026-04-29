# This is a pure cleanup script to remove all the resources created during the experiment. It will delete the "mesh-exp" namespace and also remove the label from the node.


#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="mesh-exp"
NODE_NAME="ssp-worker-1"
NODE_LABEL_KEY="exp"

# ==============================
# LOGGING HELPERS
# ==============================
log() {
  echo -e "\n[INFO] $1"
}

warn() {
  echo -e "\n[WARN] $1"
}

fail() {
  echo -e "\n[ERROR] $1"
  exit 1
}

# ==============================
# STEP 0 — PRE-CHECKS
# Ensures cluster connectivity and node presence
# ==============================
log "Checking kubectl connectivity..."
kubectl cluster-info > /dev/null || fail "kubectl not connected to cluster"

log "Checking if node exists..."
kubectl get node "$NODE_NAME" > /dev/null || warn "Node $NODE_NAME not found (skipping node label removal)"

# ==============================
# STEP 1 — KILL ANY RUNNING EBPF PROBES
# Ensures no lingering bpftrace processes on worker node
# ==============================
log "Stopping any running eBPF probes on $NODE_NAME..."
ssh "$NODE_NAME" "sudo pkill -f bpftrace" > /dev/null 2>&1 || warn "No bpftrace processes found (or SSH failed)"

# ==============================
# STEP 2 — DELETE NAMESPACE
# Removes all experiment workloads
# ==============================
log "Deleting namespace: $NAMESPACE"

if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  kubectl delete namespace "$NAMESPACE"

  log "Waiting for namespace to terminate..."
  kubectl wait --for=delete ns/"$NAMESPACE" --timeout=180s \
    || warn "Namespace deletion taking longer than expected"
else
  warn "Namespace does not exist, skipping"
fi

# ==============================
# STEP 3 — REMOVE NODE LABEL
# Cleans up scheduling constraint
# ==============================
log "Removing node label from $NODE_NAME"

if kubectl get node "$NODE_NAME" > /dev/null 2>&1; then
  kubectl label node "$NODE_NAME" "$NODE_LABEL_KEY"- > /dev/null 2>&1 \
    || warn "Label may not exist or already removed"
else
  warn "Node not found, skipping label removal"
fi

# ==============================
# STEP 4 — VERIFY CLEANUP
# Ensures environment reset (IMPORTANT for repeatability)
# ==============================
log "Verifying cleanup..."

echo ""
echo "========== VERIFICATION =========="

# Namespace check
if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  warn "Namespace still exists → cleanup incomplete"
else
  echo "✔ Namespace removed"
fi

# Node label check
if kubectl get node "$NODE_NAME" --show-labels 2>/dev/null | grep -q "$NODE_LABEL_KEY"; then
  warn "Node label still present → cleanup incomplete"
else
  echo "✔ Node label removed"
fi

# eBPF processes check
if ssh "$NODE_NAME" "pgrep -f bpftrace" > /dev/null 2>&1; then
  warn "bpftrace processes still running on $NODE_NAME"
else
  echo "✔ No lingering eBPF probes"
fi

echo "=================================="

# ==============================
# FINAL STATUS
# ==============================
log "Cleanup COMPLETE 🧹"

echo -e "\n========== SUMMARY =========="
echo "Namespace: $NAMESPACE → REMOVED"
echo "Node label: $NODE_LABEL_KEY → REMOVED (if existed)"
echo "eBPF probes: STOPPED"
echo "Cluster state: RESET"
echo "Ready for fresh experiment run"
echo "================================\n"
