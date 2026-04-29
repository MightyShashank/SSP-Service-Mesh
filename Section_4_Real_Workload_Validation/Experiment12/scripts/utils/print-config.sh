#!/bin/bash
# Print all experiment environment variables and cluster state.
# Useful for recording run configuration in data/metadata/.
#
# Usage: bash print-config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "============================================"
echo "  Experiment 12 — Configuration"
echo "============================================"

echo ""
echo "=== Cluster ==="
kubectl cluster-info 2>/dev/null | head -2 || echo "kubectl not connected"
echo ""

echo "=== Nodes ==="
kubectl get nodes -o wide 2>/dev/null || echo "N/A"
echo ""

echo "=== Node Labels ==="
kubectl get nodes --show-labels 2>/dev/null | grep -E "LABELS|role=" || echo "No labels"
echo ""

echo "=== Istio Version ==="
istioctl version 2>/dev/null || echo "istioctl not available"
echo ""

echo "=== ztunnel Pods ==="
kubectl get pods -n istio-system -l app=ztunnel -o wide 2>/dev/null || echo "N/A"
echo ""

echo "=== DSB Pods ==="
kubectl get pods -n dsb-exp -o wide 2>/dev/null || echo "N/A"
echo ""

echo "=== Load Rates ==="
if [[ -f "$ROOT_DIR/configs/wrk2/rates.env" ]]; then
  source "$ROOT_DIR/configs/wrk2/rates.env"
  echo "COMPOSE_RPS=$COMPOSE_RPS"
  echo "HOME_RPS=$HOME_RPS"
  echo "USER_RPS=$USER_RPS"
  echo "WRK2_THREADS=$WRK2_THREADS"
  echo "WRK2_CONNS=$WRK2_CONNS"
  echo "WARMUP_DURATION=$WARMUP_DURATION"
  echo "MEASURE_DURATION=$MEASURE_DURATION"
fi
echo ""

echo "=== Git Hash ==="
git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "N/A"
echo ""

echo "=== Kubernetes Version ==="
kubectl version --short 2>/dev/null || kubectl version 2>/dev/null || echo "N/A"
echo ""

echo "============================================"
