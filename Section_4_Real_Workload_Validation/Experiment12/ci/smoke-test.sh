#!/bin/bash
# Quick smoke test: verify DSB connectivity and wrk2 works.
# Run after deploy-setup.sh to confirm everything is reachable.
#
# Usage: bash smoke-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NAMESPACE="dsb-exp"
WRK2="${WRK2:-$ROOT_DIR/../wrk2/wrk}"

log()  { echo -e "\n[INFO] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

echo "============================================"
echo "  Experiment 12 — Smoke Test"
echo "============================================"

# ---- kubectl connectivity ----
log "Checking kubectl..."
kubectl cluster-info > /dev/null || fail "kubectl not connected"
tick "kubectl OK"

# ---- Namespace exists ----
log "Checking namespace..."
kubectl get namespace "$NAMESPACE" > /dev/null || fail "Namespace $NAMESPACE not found"
tick "Namespace $NAMESPACE exists"

# ---- DSB pods running ----
log "Checking DSB pods..."
RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "Running" || echo "0")
if [[ "$RUNNING" -lt 5 ]]; then
  fail "Only $RUNNING pods Running — expected at least 5"
fi
tick "$RUNNING DSB pods Running"

# ---- NGINX reachable ----
log "Checking NGINX..."
NGINX_IP=$(kubectl get svc nginx-web-server -n "$NAMESPACE" \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
[[ -n "$NGINX_IP" ]] || fail "nginx-web-server service not found"

curl -s --connect-timeout 5 "http://${NGINX_IP}:8080/" > /dev/null 2>&1 \
  || fail "NGINX not responding at $NGINX_IP:8080"
tick "NGINX reachable at $NGINX_IP:8080"

# ---- wrk2 smoke (5 seconds, 10 RPS) ----
log "Running wrk2 smoke test (5s, 10 RPS)..."
if [[ -x "$WRK2" ]]; then
  "$WRK2" -D exp -t 1 -c 5 -d 5s \
    -s "$ROOT_DIR/configs/wrk2/read-user-timeline.lua" \
    "http://${NGINX_IP}:8080/wrk2-api/user-timeline/read" -R 10 \
    > /dev/null 2>&1 \
    || fail "wrk2 smoke test failed"
  tick "wrk2 smoke test passed"
else
  echo "[WARN] wrk2 not found at $WRK2 — skipping wrk2 smoke test"
fi

echo ""
echo "============================================"
echo "  Smoke test PASSED ✅"
echo "============================================"
