#!/bin/bash
# Initialize the socfb-Reed98 social graph in DSB MongoDB — Experiment 11.
# Identical to Experiment 12 except uses namespace dsb-exp11.

set -euo pipefail

NAMESPACE="dsb-exp11"
DSB_REPO="${DSB_REPO:-/opt/dsb}"
LOCAL_PORT="${LOCAL_PORT:-18080}"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Verifying nginx-thrift service exists in $NAMESPACE..."
kubectl get svc nginx-thrift -n "$NAMESPACE" > /dev/null 2>&1 \
  || fail "nginx-thrift service not found in $NAMESPACE"
tick "nginx-thrift service found"

log "Starting kubectl port-forward (localhost:${LOCAL_PORT} → nginx-thrift:8080)..."
lsof -ti ":${LOCAL_PORT}" 2>/dev/null | xargs -r kill 2>/dev/null || true

kubectl port-forward "svc/nginx-thrift" "${LOCAL_PORT}:8080" -n "$NAMESPACE" &
PF_PID=$!
cleanup_pf() {
  if kill -0 "$PF_PID" 2>/dev/null; then
    kill "$PF_PID" 2>/dev/null || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup_pf EXIT INT TERM

log "Waiting for port-forward to become ready..."
for i in {1..30}; do
  if curl -s --connect-timeout 2 "http://127.0.0.1:${LOCAL_PORT}/" > /dev/null 2>&1; then
    tick "port-forward ready (localhost:${LOCAL_PORT} → nginx-thrift:8080)"
    break
  fi
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    fail "kubectl port-forward died — check 'kubectl get pods -n $NAMESPACE'"
  fi
  [[ "$i" -eq 30 ]] && fail "port-forward not ready after 30 attempts"
  sleep 2
done

if ! python3 -c "import aiohttp" > /dev/null 2>&1; then
  log "Installing aiohttp (required by DSB init_social_graph.py)..."
  python3 -m pip install aiohttp || fail "Failed to install aiohttp"
  tick "aiohttp installed"
fi

log "Initializing socfb-Reed98 graph (963 users, ~18,800 edges)..."
cd "${DSB_REPO}/socialNetwork" || fail "DSB socialNetwork directory not found"

python3 scripts/init_social_graph.py \
  --graph=socfb-Reed98 \
  --ip=127.0.0.1 \
  --port="${LOCAL_PORT}" \
  || fail "Social graph initialization failed"

tick "Social graph initialized (socfb-Reed98: 963 users, ~18,800 edges)"

log "Smoke test: reading user timeline for user 1..."
RESPONSE=$(curl -s --connect-timeout 5 \
  "http://127.0.0.1:${LOCAL_PORT}/wrk2-api/user-timeline/read?user_id=1&start=0&stop=5" \
  || echo "FAIL")

if echo "$RESPONSE" | grep -q "FAIL\|error\|Error"; then
  warn "Smoke test response unexpected — graph may not be fully initialized yet"
else
  tick "Smoke test passed"
fi
