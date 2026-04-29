#!/bin/bash
# Install or verify Istio Ambient Mode on the cluster.
# If Istio Ambient is already installed: verifies ztunnel DaemonSet.
# If not installed: installs using istioctl with ambient profile.
#
# Usage: bash deploy-istio-ambient.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

# ---- Check if Istio is already installed ----
log "Checking for existing Istio installation..."

if kubectl get daemonset ztunnel -n istio-system > /dev/null 2>&1; then
  tick "Istio Ambient already installed (ztunnel DaemonSet found)"

  log "Verifying ztunnel pods..."
  ZTUNNEL_COUNT=$(kubectl get pods -n istio-system -l app=ztunnel --no-headers 2>/dev/null | grep -c "Running" || echo "0")
  if [[ "$ZTUNNEL_COUNT" -lt 2 ]]; then
    warn "Only $ZTUNNEL_COUNT ztunnel pods Running — expected at least 2 (worker-0 + worker-1)"
  else
    tick "$ZTUNNEL_COUNT ztunnel pods Running"
  fi

  log "ztunnel pods:"
  kubectl get pods -n istio-system -l app=ztunnel -o wide

  # Record version
  mkdir -p "$ROOT_DIR/data/metadata"
  {
    echo "=== Istio Version ==="
    istioctl version 2>/dev/null || echo "istioctl not available — check pod labels"
    echo ""
    echo "=== ztunnel Pods ==="
    kubectl get pods -n istio-system -l app=ztunnel -o wide
  } > "$ROOT_DIR/data/metadata/software-versions.txt"

  exit 0
fi

# ---- Install Istio Ambient ----
log "Istio Ambient not found — installing..."

if ! command -v istioctl > /dev/null 2>&1; then
  fail "istioctl not found. Install from: https://istio.io/latest/docs/setup/getting-started/"
fi

istioctl install -f "$ROOT_DIR/configs/istio/install-ambient.yaml" -y \
  || fail "Istio Ambient installation failed"

log "Waiting for ztunnel DaemonSet to be ready..."
kubectl rollout status daemonset/ztunnel -n istio-system --timeout=120s \
  || fail "ztunnel DaemonSet not ready within 2 minutes"

tick "Istio Ambient installed successfully"

log "ztunnel pods:"
kubectl get pods -n istio-system -l app=ztunnel -o wide
