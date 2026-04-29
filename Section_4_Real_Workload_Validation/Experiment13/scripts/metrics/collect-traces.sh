#!/bin/bash
# Collect Jaeger distributed traces via the HTTP API.
# Fetches all compose-post traces from the measurement window.
#
# This script manages its own port-forward to avoid relying on a
# long-lived external one that may have died during the load test.
#
# Usage: bash collect-traces.sh <jaeger_ip_or_localhost> <output_file>
# Note: <jaeger_ip_or_localhost> is accepted for API compatibility but
#       this script always starts a fresh port-forward on localhost.

set -euo pipefail

OUTPUT_FILE="${2:-/tmp/jaeger-traces.json}"
NAMESPACE_OBS="observability"
LOCAL_PORT="16686"

mkdir -p "$(dirname "$OUTPUT_FILE")"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

JAEGER_URL="http://127.0.0.1:${LOCAL_PORT}"

# ── Start a fresh port-forward ──────────────────────────────────────────────
log "Starting fresh Jaeger port-forward on localhost:${LOCAL_PORT}..."
pkill -f "kubectl port-forward svc/jaeger-query ${LOCAL_PORT}:${LOCAL_PORT}" || true
sleep 1

kubectl port-forward svc/jaeger-query "${LOCAL_PORT}:${LOCAL_PORT}" \
  -n "$NAMESPACE_OBS" &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT INT TERM

# Wait for port-forward to become ready (up to 30s)
READY=false
for i in $(seq 1 15); do
  if curl -s --connect-timeout 2 "${JAEGER_URL}/api/services" > /dev/null 2>&1; then
    READY=true
    break
  fi
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    warn "Jaeger port-forward process died unexpectedly"
    exit 0
  fi
  sleep 2
done

if [[ "$READY" != "true" ]]; then
  warn "Jaeger not reachable at ${JAEGER_URL} after 30s — skipping trace collection"
  exit 0
fi

tick "Jaeger reachable at ${JAEGER_URL}"

# ── Fetch compose-post traces ────────────────────────────────────────────────
log "Fetching compose-post traces..."
curl -s \
  "${JAEGER_URL}/api/traces?service=compose-post&limit=5000&lookback=2h" \
  -o "$OUTPUT_FILE" \
  || { warn "Failed to fetch compose-post traces"; exit 0; }

TRACE_COUNT=$(python3 -c "
import json, sys
try:
  d = json.load(open('${OUTPUT_FILE}'))
  print(len(d.get('data', [])))
except:
  print(0)
" 2>/dev/null || echo "0")

tick "Collected ${TRACE_COUNT} compose-post traces → $OUTPUT_FILE"

# ── Also collect nginx-frontend traces ──────────────────────────────────────
log "Fetching nginx-frontend traces..."
NGINX_TRACES="$(dirname "$OUTPUT_FILE")/jaeger-traces-nginx.json"
curl -s \
  "${JAEGER_URL}/api/traces?service=nginx-thrift&limit=2000&lookback=1h" \
  -o "$NGINX_TRACES" \
  || warn "Failed to fetch nginx traces"

log "Trace collection complete"
