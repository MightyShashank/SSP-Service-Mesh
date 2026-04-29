#!/bin/bash
# Remove Istio CRDs and DaemonSets.
# WARNING: This removes Istio from the entire cluster, not just from the experiment.
# Only use if you want to fully reset the mesh.
#
# Usage: ./cleanup-istio.sh

set -euo pipefail

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Removing Istio..."

if command -v istioctl > /dev/null 2>&1; then
  log "Using istioctl to uninstall..."
  istioctl uninstall --purge -y 2>/dev/null || warn "istioctl uninstall failed — trying manual cleanup"
else
  warn "istioctl not found — using manual cleanup"
fi

log "Deleting istio-system namespace..."
kubectl delete namespace istio-system 2>/dev/null \
  || warn "istio-system namespace not found"

log "Deleting Istio CRDs..."
kubectl get crds -o name | grep 'istio.io' | xargs -r kubectl delete 2>/dev/null \
  || warn "No Istio CRDs found"

tick "Istio removed"
echo ""
echo "WARNING: Istio is no longer installed on this cluster."
echo "Re-install with: bash scripts/deploy/deploy-istio-ambient.sh"
