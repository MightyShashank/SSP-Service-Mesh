# Pure deploy for Experiment 4

#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="mesh-exp"
NODE_NAME="ssp-worker-1"

CLUSTER_SETUP_DIR="../cluster-setup"
WORKLOADS_DIR="../workloads"

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
# Ensures cluster connectivity and node existence
# ==============================
log "Checking kubectl connectivity..."
kubectl cluster-info > /dev/null || fail "kubectl not connected"

log "Checking if node exists..."
kubectl get node "$NODE_NAME" > /dev/null || fail "Node $NODE_NAME not found"

# ==============================
# STEP 1 — CREATE NAMESPACE
# Enables Istio Ambient Mesh
# ==============================
log "Creating namespace with ambient mesh enabled..."
kubectl apply -f "$CLUSTER_SETUP_DIR/namespace.yaml"

# ==============================
# STEP 2 — LABEL NODE
# Forces deterministic scheduling → SAME NODE → SAME ztunnel
# ==============================
log "Labeling node for deterministic scheduling..."
bash "$CLUSTER_SETUP_DIR/node-label.sh"

# ==============================
# STEP 3 — DEPLOY WORKLOADS
# svc-a → latency-sensitive (VIP)
# svc-b → noisy neighbor (throughput-oriented)
# ==============================
log "Deploying svc-a and svc-b..."
kubectl apply -f "$WORKLOADS_DIR/svc-a-deployment.yaml"
kubectl apply -f "$WORKLOADS_DIR/svc-b-deployment.yaml"

log "Creating services..."
kubectl apply -f "$WORKLOADS_DIR/services.yaml"

# ==============================
# STEP 4 — DEPLOY CLIENT (FORTIO)
# Client generates traffic INSIDE cluster (no external noise)
# ==============================
log "Deploying Fortio client..."
kubectl apply -f "$WORKLOADS_DIR/client.yaml"

# ==============================
# STEP 5 — WAIT FOR ALL PODS
# Ensures svc-a, svc-b, client are ready
# ==============================
log "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=180s \
  || fail "Pods not ready in time"

# ==============================
# STEP 6 — VERIFY POD PLACEMENT
# CRITICAL: ensures SAME NODE → SAME ztunnel
# ==============================
log "Verifying pod placement..."

kubectl get pods -n "$NAMESPACE" -o wide

NODE_SVC_A=$(kubectl get pod -n "$NAMESPACE" -l app=svc-a -o jsonpath='{.items[0].spec.nodeName}')
NODE_SVC_B=$(kubectl get pod -n "$NAMESPACE" -l app=svc-b -o jsonpath='{.items[0].spec.nodeName}')
NODE_CLIENT=$(kubectl get pod -n "$NAMESPACE" -l app=client -o jsonpath='{.items[0].spec.nodeName}')

echo ""
echo "Pod → Node mapping:"
echo "svc-a   → $NODE_SVC_A"
echo "svc-b   → $NODE_SVC_B"
echo "client  → $NODE_CLIENT"

if [[ "$NODE_SVC_A" == "$NODE_SVC_B" && "$NODE_SVC_A" == "$NODE_CLIENT" ]]; then
  echo "✔ All pods scheduled on SAME node → $NODE_SVC_A"
else
  fail "Pods are NOT on same node → experiment INVALID"
fi

# ==============================
# STEP 7 — VERIFY ZTUNNEL
# Ensures ambient dataplane is active on node
# ==============================
log "Verifying ztunnel presence..."

kubectl get pods -n istio-system -o wide | grep ztunnel || fail "ztunnel not found"

ZTUNNEL_NODE=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$NODE_SVC_A" '$0 ~ "ztunnel" && $7 == node {print $1}')

if [[ -z "$ZTUNNEL_NODE" ]]; then
  fail "No ztunnel on node $NODE_SVC_A → experiment INVALID"
fi

echo "✔ ztunnel on node → $ZTUNNEL_NODE"

# ==============================
# STEP 8 — VERIFY CLIENT TOOLING (FORTIO)
# Ensures Fortio is available inside client pod
# ==============================
log "Verifying Fortio inside client..."

if kubectl exec -n "$NAMESPACE" client -- fortio version > /dev/null 2>&1; then
  echo "✔ Fortio available in client pod"
else
  fail "Fortio not installed in client pod"
fi

# ==============================
# STEP 9 — VERIFY BPFTRACE ON WORKER NODE
# Ensures eBPF instrumentation is possible
# ==============================
log "Checking bpftrace on worker node ($NODE_NAME)..."

if ssh "$NODE_NAME" "which bpftrace" > /dev/null 2>&1; then
  echo "✔ bpftrace available on $NODE_NAME"
else
  warn "bpftrace NOT found on $NODE_NAME — run ebpf/install-bpftrace.sh on the worker"
fi

# ==============================
# FINAL SUMMARY
# ==============================
log "Deployment COMPLETE ✅"

echo -e "\n========== SUMMARY =========="
echo "Namespace: $NAMESPACE (ambient enabled)"
echo "Node: $NODE_NAME"
echo "Pods: svc-a, svc-b, client"
echo "Placement: SAME NODE → $NODE_SVC_A"
echo "Dataplane: ztunnel → $ZTUNNEL_NODE"
echo "Client Tool: Fortio"
echo "eBPF Tool: bpftrace (check on worker)"
echo "Status: READY FOR EXPERIMENT"
echo "================================\n"
