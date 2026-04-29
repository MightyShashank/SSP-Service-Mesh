#!/bin/bash
# Pure cleanup: teardown DSB, Jaeger, node labels, namespace.
# Leaves Istio Ambient in place (does NOT remove Istio).
# Use this before a completely fresh manual deployment.
#
# Usage: ./cleanup.sh

set -euo pipefail

NAMESPACE="dsb-exp"
NAMESPACE_OBS="observability"
WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"
LOAD_GEN="default-pool-ssp-865907b54154"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Checking kubectl connectivity..."
kubectl cluster-info > /dev/null || fail "kubectl not connected"

# ==============================
# STEP 1 — UNINSTALL DSB VIA HELM
# ==============================
log "Uninstalling DSB Social-Network Helm release..."
helm uninstall social-network -n "$NAMESPACE" 2>/dev/null \
  || warn "DSB Helm release not found, skipping"

# ==============================
# STEP 2 — DELETE NAMESPACE
# ==============================
log "Deleting namespace: $NAMESPACE..."
if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  kubectl delete namespace "$NAMESPACE"
  log "Waiting for namespace to terminate..."
  kubectl wait --for=delete ns/"$NAMESPACE" --timeout=180s \
    || warn "Namespace deletion taking longer than expected"
  tick "Namespace $NAMESPACE deleted"
else
  warn "Namespace $NAMESPACE does not exist, skipping"
fi

# ==============================
# STEP 3 — REMOVE OBSERVABILITY
# ==============================
log "Removing Jaeger from observability namespace..."
kubectl delete deployment jaeger -n "$NAMESPACE_OBS" 2>/dev/null || true
kubectl delete service jaeger-query jaeger-collector -n "$NAMESPACE_OBS" 2>/dev/null || true

# ==============================
# STEP 4 — REMOVE NODE LABELS
# ==============================
log "Removing node labels..."
kubectl label node "$WORKER_0" role- exp- > /dev/null 2>&1 || true
kubectl label node "$WORKER_1" role- exp- > /dev/null 2>&1 || true
kubectl label node "$LOAD_GEN" role- exp- > /dev/null 2>&1 || true
tick "Node labels removed"

# ==============================
# STEP 5 — VERIFY
# ==============================
log "Verifying cleanup..."
echo ""
echo "========== VERIFICATION =========="

if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  warn "Namespace $NAMESPACE still exists"
else
  echo "✔ Namespace $NAMESPACE removed"
fi

if kubectl get node "$WORKER_0" --show-labels 2>/dev/null | grep -q "role="; then
  warn "Node labels still present on $WORKER_0"
else
  echo "✔ Node labels removed"
fi
echo "=================================="

log "Cleanup COMPLETE 🧹"
echo ""
echo "Istio Ambient remains installed."
echo "Run 'bash scripts/deploy/deploy-setup.sh' to redeploy."
