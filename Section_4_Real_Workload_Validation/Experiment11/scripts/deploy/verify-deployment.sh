#!/bin/bash
# Verify Experiment 11 deployment (plain K8s, NO Istio).
# Checks: pod placement, NGINX IP, Jaeger, all pods Running.
# NOTE: No ztunnel checks — this experiment has NO Istio.

set -euo pipefail

NAMESPACE="dsb-exp11"
WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"
NAMESPACE_OBS="observability"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

echo ""
echo "============================================"
echo "  Experiment 11 — Deployment Verification"
echo "  (plain K8s, NO Istio/ztunnel)"
echo "============================================"

# ---- Check nodes ----
log "Checking nodes..."
kubectl get nodes | grep -v "^NAME" | while read -r line; do
  NODE=$(echo "$line" | awk '{print $1}')
  STATUS=$(echo "$line" | awk '{print $2}')
  if [[ "$STATUS" != "Ready" ]]; then
    fail "Node $NODE is not Ready"
  fi
done
tick "All nodes Ready"

# ---- Confirm NO ztunnel / Istio is active ----
log "Confirming cluster has NO Istio ambient active in namespace..."
if kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels}' 2>/dev/null \
    | grep -q "istio.io/dataplane-mode"; then
  warn "Namespace $NAMESPACE has Istio ambient label set — this should NOT be the case for Experiment 11"
  warn "Remove label: kubectl label namespace $NAMESPACE istio.io/dataplane-mode-"
else
  tick "Namespace $NAMESPACE has NO Istio ambient label (correct)"
fi

# ---- Check DSB pods on worker-0 ----
log "Verifying victim-tier pods on worker-0..."
VICTIM_SERVICES=("social-graph-service" "user-service" "media-service" "url-shorten-service" "text-service" "unique-id-service" "user-mention-service")
ALL_OK=true

for SVC in "${VICTIM_SERVICES[@]}"; do
  NODE=$(kubectl get pod -n "$NAMESPACE" -l service="$SVC" \
    -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "NOT_FOUND")
  if [[ "$NODE" == "$WORKER_0" ]]; then
    echo "  ✔ $SVC → worker-0"
  elif [[ "$NODE" == "NOT_FOUND" ]]; then
    warn "  ✘ $SVC pod not found (label: service=$SVC)"
    ALL_OK=false
  else
    warn "  ✘ $SVC → $NODE (expected worker-0)"
    ALL_OK=false
  fi
done

if [[ "$ALL_OK" == "false" ]]; then
  warn "Some victim-tier pods are not on worker-0 — Experiment may be INVALID"
else
  tick "All victim-tier pods on worker-0"
fi

# ---- Check NGINX ClusterIP ----
log "Getting NGINX ClusterIP..."
NGINX_IP=$(kubectl get svc nginx-thrift -n "$NAMESPACE" \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [[ -z "$NGINX_IP" ]]; then
  fail "nginx-thrift service not found in $NAMESPACE"
fi
tick "NGINX ClusterIP → $NGINX_IP"

# ---- Check Jaeger ----
log "Verifying Jaeger..."
JAEGER_IP=$(kubectl get svc jaeger-query -n "$NAMESPACE_OBS" \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [[ -z "$JAEGER_IP" ]]; then
  warn "Jaeger not found in observability namespace — traces will not be collected"
else
  tick "Jaeger ClusterIP → $JAEGER_IP (port 16686)"
fi

# ---- Check all DSB pods are Running ----
log "Checking all DSB pods are Running..."
NOT_RUNNING=$(kubectl get pods -n "$NAMESPACE" | grep -v "^NAME" | grep -v "Running" | grep -v "Completed" || true)
if [[ -n "$NOT_RUNNING" ]]; then
  warn "Some pods are not Running:"
  echo "$NOT_RUNNING"
else
  tick "All DSB pods Running"
fi

# ---- All done ----
echo ""
echo "============================================"
echo "  Verification Summary"
echo "============================================"
echo "Namespace:   $NAMESPACE (plain K8s — NO Istio)"
echo "NGINX IP:    $NGINX_IP"
echo "Jaeger IP:   ${JAEGER_IP:-N/A}"
echo "ztunnel:     N/A (this experiment has NO Istio)"
echo "============================================"
echo ""
echo "→ If all checks passed: run 'bash scripts/run/run_sequential_experiments.sh 5'"
