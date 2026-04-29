#!/bin/bash
# Deploy DeathStarBench Social-Network via Helm.
# Uses ambient-mode Helm values + node-affinity placement overlays.
#
# Usage: bash deploy-dsb.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp"
DSB_REPO="${DSB_REPO:-/opt/dsb}"
DSB_CHART="${DSB_REPO}/socialNetwork/helm-chart/socialnetwork"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

# ---- Ensure DSB repo + Helm chart are present ----
# A directory can exist from a partial/failed clone — check Chart.yaml specifically.
if [[ ! -f "$DSB_CHART/Chart.yaml" ]]; then
  log "DSB Helm chart missing (no Chart.yaml at $DSB_CHART)"
  if [[ -d "$DSB_REPO" && ! -d "$DSB_REPO/.git" ]]; then
    log "Removing broken DSB directory (no .git) at $DSB_REPO ..."
    sudo rm -rf "$DSB_REPO"
  fi
  if [[ ! -d "$DSB_REPO/.git" ]]; then
    log "Cloning DeathStarBench to $DSB_REPO ..."
    sudo git clone https://github.com/delimitrou/DeathStarBench.git "$DSB_REPO" \
      || fail "Failed to clone DSB. Check internet access and sudo."
    tick "DeathStarBench cloned"
  fi
  [[ -f "$DSB_CHART/Chart.yaml" ]] \
    || fail "Chart.yaml still missing after clone — unexpected repo structure at $DSB_CHART"
fi
log "DSB chart: $DSB_CHART"
helm version > /dev/null || fail "helm not found"

# ---- Ensure namespace exists ----
kubectl get namespace "$NAMESPACE" > /dev/null 2>&1 \
  || kubectl apply -f "$ROOT_DIR/configs/kubernetes/namespace.yaml"

# ---- Deploy DSB via Helm ----
log "Deploying DSB Social-Network via Helm..."
log "Chart: $DSB_CHART"
log "Namespace: $NAMESPACE"

helm upgrade --install social-network "$DSB_CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$ROOT_DIR/configs/deathstarbench/social-network/base/helm-values-ambient.yaml" \
  --values "$ROOT_DIR/configs/deathstarbench/social-network/placement/worker0-affinity.yaml" \
  --values "$ROOT_DIR/configs/deathstarbench/social-network/placement/worker1-affinity.yaml" \
  --timeout 300s \
  --wait \
  || fail "Helm install failed"

tick "DSB Social-Network deployed"

# ---- Wait for pods ----
log "Waiting for all DSB pods to be Ready..."
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=300s \
  || fail "Some pods did not become Ready within 5 minutes"

tick "All DSB pods Ready"
kubectl get pods -n "$NAMESPACE" -o wide
