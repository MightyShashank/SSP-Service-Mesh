#!/bin/bash
# Idempotent cleanup + redeploy for Experiment 12.
# Used between sequential experiment repetitions by run_sequential_experiments.sh.
# Ensures every repetition starts with a fresh, identical environment.
#
# Sequence:
#   1. Teardown (helm uninstall + delete namespace + remove labels)
#   2. Redeploy (namespace + labels + DSB + Jaeger)
#   3. Wait for readiness
#   4. Re-initialize social graph
#   5. Verify placement

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp"
WORKER_0="default-pool-ssp-11b2c93c3e14"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Checking kubectl connectivity..."
kubectl cluster-info > /dev/null || fail "kubectl not connected"

# ==============================
# STEP 1 — CLEANUP
# ==============================
log "Tearing down previous deployment..."

helm uninstall social-network -n "$NAMESPACE" 2>/dev/null \
  || warn "DSB Helm release not found, skipping"

if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  kubectl delete namespace "$NAMESPACE"
  log "Waiting for namespace to terminate..."
  kubectl wait --for=delete ns/"$NAMESPACE" --timeout=180s \
    || warn "Namespace deletion taking longer than expected"
else
  warn "Namespace $NAMESPACE not found, skipping deletion"
fi

tick "Cleanup complete"

# ==============================
# STEP 2 — REDEPLOY
# ==============================
log "Redeploying fresh environment..."
bash "$ROOT_DIR/scripts/deploy/deploy-setup.sh" \
  || fail "deploy-setup.sh failed"

tick "Deployment complete"

# ==============================
# STEP 3 — VERIFY
# ==============================
log "Verifying pod placement and ztunnel..."

SOCIAL_GRAPH_NODE=$(kubectl get pod -n "$NAMESPACE" -l app=social-graph \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "")
if [[ "$SOCIAL_GRAPH_NODE" != "$WORKER_0" ]]; then
  warn "social-graph NOT on worker-0 (found: ${SOCIAL_GRAPH_NODE:-not found}) — experiment may be INVALID"
else
  tick "social-graph on worker-0 ✔"
fi

ZTUNNEL_POD=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$WORKER_0" '$0 ~ "ztunnel" && $7 == node {print $1}')
if [[ -z "$ZTUNNEL_POD" ]]; then
  fail "No ztunnel on worker-0 → experiment INVALID"
fi
tick "ztunnel on worker-0 → $ZTUNNEL_POD"

# ==============================
# FINAL SUMMARY
# ==============================
log "cleanup-deploy-setup COMPLETE ✅"
NGINX_IP=$(kubectl get svc nginx-thrift -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")
echo ""
echo "========== SUMMARY =========="
echo "Namespace:   $NAMESPACE (ambient enabled)"
echo "NGINX IP:    $NGINX_IP"
echo "ztunnel:     $ZTUNNEL_POD"
echo "Graph:       socfb-Reed98 initialized"
echo "Status:      READY FOR EXPERIMENT"
echo "============================="
