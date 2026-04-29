#!/bin/bash
# Experiment 11 — Pure cleanup (teardown only, no redeploy).

set -euo pipefail
NAMESPACE="dsb-exp11"
log() { echo -e "\n[CLEAN] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Uninstalling DSB Helm release..."
helm uninstall social-network-exp11 -n "$NAMESPACE" 2>/dev/null || true

log "Deleting namespace $NAMESPACE..."
kubectl delete namespace "$NAMESPACE" --timeout=120s 2>/dev/null || true

tick "Cleanup complete (namespace $NAMESPACE removed)"
