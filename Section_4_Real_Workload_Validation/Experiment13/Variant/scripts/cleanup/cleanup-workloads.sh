#!/bin/bash
# Delete DSB workloads only (keep Istio, keep namespace).
# Use this for quick iteration without full teardown.
#
# Usage: ./cleanup-workloads.sh

set -euo pipefail

NAMESPACE="dsb-exp"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Uninstalling DSB Social-Network Helm release..."
helm uninstall social-network -n "$NAMESPACE" 2>/dev/null \
  || warn "DSB Helm release not found, skipping"

log "Deleting any remaining DSB pods..."
kubectl delete pods --all -n "$NAMESPACE" --grace-period=30 2>/dev/null || true

log "Waiting for pods to terminate..."
kubectl wait --for=delete pods --all -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

tick "DSB workloads removed (namespace and Istio preserved)"
