#!/bin/bash
# Capture Prometheus metrics snapshot via the Prometheus HTTP API.
# Queries ztunnel CPU, request latency, and throughput.
#
# Usage: bash capture-prometheus-snapshot.sh <output_dir>

set -euo pipefail

NAMESPACE_OBS="observability"
OUTPUT_DIR="${1:-/tmp/prom-snapshot}"
mkdir -p "$OUTPUT_DIR"

log() { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }

PROM_IP=$(kubectl get svc prometheus-server -n "$NAMESPACE_OBS" \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [[ -z "$PROM_IP" ]]; then
  warn "Prometheus not found — skipping snapshot"
  exit 0
fi

PROM_URL="http://${PROM_IP}:80"

log "Querying Prometheus at $PROM_URL..."

# ztunnel CPU usage
log "Querying ztunnel CPU..."
curl -s "${PROM_URL}/api/v1/query?query=rate(container_cpu_usage_seconds_total{pod=~\"ztunnel.*\"}[1m])" \
  > "$OUTPUT_DIR/ztunnel-cpu.json" 2>/dev/null || warn "ztunnel CPU query failed"

# Istio request duration P99
log "Querying request latency P99..."
curl -s "${PROM_URL}/api/v1/query?query=histogram_quantile(0.99,rate(istio_request_duration_milliseconds_bucket[1m]))" \
  > "$OUTPUT_DIR/request-latency-p99.json" 2>/dev/null || warn "Latency query failed"

# Request throughput
log "Querying request throughput..."
curl -s "${PROM_URL}/api/v1/query?query=rate(istio_requests_total[1m])" \
  > "$OUTPUT_DIR/request-throughput.json" 2>/dev/null || warn "Throughput query failed"

# Network throughput
log "Querying network throughput..."
curl -s "${PROM_URL}/api/v1/query?query=rate(container_network_transmit_bytes_total[1m])" \
  > "$OUTPUT_DIR/network-throughput.json" 2>/dev/null || warn "Network query failed"

log "Prometheus snapshot saved to $OUTPUT_DIR"
