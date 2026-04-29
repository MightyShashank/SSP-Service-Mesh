# Cleanup and then deploy (idempotent) for Experiment 4

#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="mesh-exp"
NODE_NAME="ssp-worker-1"
NODE_LABEL_KEY="exp"
NODE_LABEL_VALUE="mesh"

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
kubectl cluster-info > /dev/null || fail "kubectl not connected to cluster"

log "Checking if target node exists..."
kubectl get node "$NODE_NAME" > /dev/null || fail "Node $NODE_NAME not found"

# ==============================
# STEP 1 — CLEANUP (IDEMPOTENT)
# Removes previous experiment state
# ==============================
log "Cleaning up previous experiment (if exists)..."

# Kill any running eBPF probes
ssh "$NODE_NAME" "sudo pkill -f bpftrace" > /dev/null 2>&1 || true

if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  kubectl delete namespace "$NAMESPACE"
  log "Waiting for namespace termination..."
  kubectl wait --for=delete ns/"$NAMESPACE" --timeout=120s || warn "Namespace deletion taking longer than expected"
else
  warn "Namespace does not exist, skipping deletion"
fi

log "Removing node label (if exists)..."
kubectl label node "$NODE_NAME" "$NODE_LABEL_KEY"- > /dev/null 2>&1 || true

# ==============================
# STEP 2 — SETUP NAMESPACE
# Enables Istio Ambient Mesh via namespace label
# ==============================
log "Creating namespace with ambient mesh enabled..."
kubectl apply -f "$CLUSTER_SETUP_DIR/namespace.yaml"

# ==============================
# STEP 3 — LABEL NODE
# Forces deterministic scheduling → SAME NODE → SAME ztunnel
# ==============================
log "Labeling node for deterministic scheduling..."
kubectl label node "$NODE_NAME" "$NODE_LABEL_KEY"="$NODE_LABEL_VALUE" --overwrite

# ==============================
# STEP 4 — DEPLOY WORKLOADS
# svc-a → latency-sensitive (VIP)
# svc-b → noisy neighbor (throughput-oriented)
# ==============================
log "Deploying svc-a and svc-b..."
kubectl apply -f "$WORKLOADS_DIR/svc-a-deployment.yaml"
kubectl apply -f "$WORKLOADS_DIR/svc-b-deployment.yaml"

log "Creating services..."
kubectl apply -f "$WORKLOADS_DIR/services.yaml"

# ==============================
# STEP 5 — DEPLOY CLIENT
# Client runs Fortio → generates traffic INSIDE cluster
# Ensures no external network noise
# ==============================
log "Deploying Fortio client..."
kubectl apply -f "$WORKLOADS_DIR/client.yaml"

# ==============================
# STEP 6 — WAIT FOR READINESS
# Ensures ALL pods (svc-a, svc-b, client) are ready
# ==============================
log "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=180s \
  || fail "Pods did not become ready in time"

# ==============================
# STEP 7 — VERIFY POD PLACEMENT
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
  fail "Pods are NOT on the same node → experiment INVALID"
fi

# ==============================
# STEP 8 — VERIFY ZTUNNEL
# Ensures node has ztunnel (ambient dataplane)
# ==============================
log "Verifying ztunnel presence..."

kubectl get pods -n istio-system -o wide | grep ztunnel || fail "No ztunnel pods found"

ZTUNNEL_NODE=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$NODE_SVC_A" '$0 ~ "ztunnel" && $7 == node {print $1}')

if [[ -z "$ZTUNNEL_NODE" ]]; then
  fail "No ztunnel running on node $NODE_SVC_A → experiment INVALID"
fi

echo "✔ ztunnel on node $NODE_SVC_A → $ZTUNNEL_NODE"

# ==============================
# STEP 9 — VERIFY CLIENT TOOLING (FORTIO)
# Ensures Fortio is available inside client pod
# ==============================
log "Verifying Fortio availability inside client..."

if kubectl exec -n "$NAMESPACE" client -- fortio version > /dev/null 2>&1; then
  echo "✔ Fortio is available inside client pod"
else
  fail "Fortio not available inside client pod"
fi

# ==============================
# STEP 10 — VERIFY BPFTRACE ON WORKER NODE
# ==============================
log "Checking bpftrace on $NODE_NAME..."

if ssh "$NODE_NAME" "which bpftrace" > /dev/null 2>&1; then
  echo "✔ bpftrace available on $NODE_NAME"
else
  warn "bpftrace NOT found on $NODE_NAME — run ebpf/install-bpftrace.sh on the worker node"
fi

# ==============================
# FINAL SUMMARY
# ==============================
log "Experiment setup COMPLETE ✅"

echo -e "\n========== SUMMARY =========="
echo "Namespace: $NAMESPACE (ambient enabled)"
echo "Node: $NODE_NAME (labeled $NODE_LABEL_KEY=$NODE_LABEL_VALUE)"
echo "Pods: svc-a, svc-b, client"
echo "Placement: SAME NODE → $NODE_SVC_A"
echo "Dataplane: ztunnel → $ZTUNNEL_NODE"
echo "Client Tool: Fortio"
echo "eBPF Tool: bpftrace"
echo "Status: READY FOR EXPERIMENTATION"
echo "================================\n"
