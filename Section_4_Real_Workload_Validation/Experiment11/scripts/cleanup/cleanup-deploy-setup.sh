#!/bin/bash
# Experiment 11 — Cleanup-and-Redeploy (idempotent, used between repetitions).
# Tears down the DSB release in dsb-exp11, re-creates the namespace (plain, no Istio),
# re-deploys DSB and re-initializes the social graph.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp11"
DSB_REPO="${DSB_REPO:-/opt/dsb}"

log()  { echo -e "\n[RESET] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Cleanup: deleting DSB Helm release from $NAMESPACE..."
helm uninstall social-network-exp11 -n "$NAMESPACE" 2>/dev/null || true

log "Deleting namespace $NAMESPACE..."
kubectl delete namespace "$NAMESPACE" --timeout=120s 2>/dev/null || true

log "Waiting for namespace to terminate..."
for i in $(seq 1 30); do
  kubectl get namespace "$NAMESPACE" > /dev/null 2>&1 || { tick "Namespace gone"; break; }
  sleep 5
done

log "Re-deploying..."
DSB_REPO="$DSB_REPO" bash "$ROOT_DIR/scripts/deploy/deploy-setup.sh"
tick "Cleanup + redeploy complete"
