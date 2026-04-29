#!/bin/bash
# Verify Experiment 12 deployment is correct before running.
# Checks: pod placement, ztunnel on worker-0, Jaeger, NGINX IP.

set -euo pipefail

NAMESPACE="dsb-exp"
WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"
NAMESPACE_OBS="observability"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

echo ""
echo "============================================"
echo "  Experiment 12 — Deployment Verification"
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

# ---- Check DSB pods on worker-0 ----
log "Verifying victim-tier pods on worker-0..."
# DSB chart uses label 'service=<name>' (not 'app=') — check _baseDeployment.tpl
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

# ---- Check ztunnel on worker-0 ----
log "Verifying ztunnel on worker-0..."
ZTUNNEL_POD=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$WORKER_0" '$0 ~ "ztunnel" && $7 == node {print $1}')

if [[ -z "$ZTUNNEL_POD" ]]; then
  fail "No ztunnel DaemonSet pod found on worker-0 → experiment INVALID"
fi
tick "ztunnel on worker-0 → $ZTUNNEL_POD"

# ---- Check ztunnel on worker-1 ----
log "Verifying ztunnel on worker-1..."
ZTUNNEL_W1=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$WORKER_1" '$0 ~ "ztunnel" && $7 == node {print $1}')

if [[ -z "$ZTUNNEL_W1" ]]; then
  warn "No ztunnel on worker-1 — mid-tier traffic will not be in ambient mesh"
else
  tick "ztunnel on worker-1 → $ZTUNNEL_W1"
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
echo "Namespace:       $NAMESPACE (ambient enabled)"
echo "NGINX IP:        $NGINX_IP"
echo "ztunnel (w0):   $ZTUNNEL_POD"
echo "Jaeger IP:       ${JAEGER_IP:-N/A}"
echo "============================================"
echo ""
echo "→ If all checks passed: run 'bash scripts/run/run_sequential_experiments.sh 5'"
