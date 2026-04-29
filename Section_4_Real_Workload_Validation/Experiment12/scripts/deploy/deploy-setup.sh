#!/bin/bash
# Experiment 12 — End-to-End Deploy Script
# Runs in order:
#   1. Node labels
#   2. Namespace + Istio config
#   3. DSB Social-Network via Helm
#   4. Jaeger on worker-1
#   5. Wait for all pods
#   6. Initialize social graph
#   7. Verify placement and ztunnel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp"
WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"

DSB_REPO="${DSB_REPO:-/opt/dsb}"            # Set DSB_REPO env var to override
DSB_CHART="${DSB_REPO}/socialNetwork/helm-chart/socialnetwork"
HELM_VALUES_AMBIENT="$ROOT_DIR/configs/deathstarbench/social-network/base/helm-values-ambient.yaml"
HELM_PLACEMENT_W0="$ROOT_DIR/configs/deathstarbench/social-network/placement/worker0-affinity.yaml"
HELM_PLACEMENT_W1="$ROOT_DIR/configs/deathstarbench/social-network/placement/worker1-affinity.yaml"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

# ==============================
# STEP 0 — PRE-CHECKS
# ==============================
log "Checking prerequisites..."
kubectl cluster-info > /dev/null || fail "kubectl not connected to cluster"
helm version > /dev/null         || fail "helm not found — install helm 3.x"
tick "Prerequisites OK"

# ==============================
# STEP 0B — ENSURE DSB REPO
# A directory can exist from a failed clone; check for Chart.yaml specifically.
# ==============================
if [[ ! -f "$DSB_CHART/Chart.yaml" ]]; then
  log "DSB Helm chart not found (Chart.yaml missing at $DSB_CHART)"
  if [[ -d "$DSB_REPO" && ! -d "$DSB_REPO/.git" ]]; then
    log "Removing incomplete DSB directory (no .git found) at $DSB_REPO ..."
    sudo rm -rf "$DSB_REPO"
  fi
  if [[ ! -d "$DSB_REPO/.git" ]]; then
    log "Cloning DeathStarBench to $DSB_REPO — this takes ~1 minute..."
    sudo git clone https://github.com/delimitrou/DeathStarBench.git "$DSB_REPO" \
      || fail "Failed to clone DeathStarBench. Check internet / sudo access."
    tick "DeathStarBench cloned → $DSB_REPO"
  fi
  [[ -f "$DSB_CHART/Chart.yaml" ]] \
    || fail "Chart.yaml still missing at $DSB_CHART after clone — unexpected repo structure"
fi
tick "DSB chart confirmed → $DSB_CHART"

# ==============================
# STEP 1 — LABEL NODES
# ==============================
log "Labeling cluster nodes..."
bash "$ROOT_DIR/configs/kubernetes/node-labels.sh"
tick "Nodes labeled"

# ==============================
# STEP 2 — CREATE NAMESPACE
# Enables Istio Ambient Mode for dsb-exp
# ==============================
log "Creating namespace with Istio Ambient enabled..."
kubectl apply -f "$ROOT_DIR/configs/kubernetes/namespace.yaml"
tick "Namespace dsb-exp created (ambient enabled)"

# ==============================
# STEP 3 — APPLY ISTIO CONFIG
# ==============================
log "Applying Istio Telemetry config (Jaeger tracing)..."
kubectl apply -f "$ROOT_DIR/configs/istio/telemetry.yaml" || warn "Telemetry apply failed — continuing"

log "Applying mTLS PeerAuthentication..."
kubectl apply -f "$ROOT_DIR/configs/istio/peer-authentication.yaml"
tick "Istio configs applied"

# ==============================
# STEP 4 — DEPLOY DSB SOCIAL-NETWORK
# ==============================
log "Deploying DeathStarBench Social-Network via Helm..."
helm upgrade --install social-network "$DSB_CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$HELM_VALUES_AMBIENT" \
  --values "$HELM_PLACEMENT_W0" \
  --values "$HELM_PLACEMENT_W1" \
  --timeout 300s \
  --wait
tick "DSB Social-Network deployed"

# ==============================
# STEP 5 — DEPLOY JAEGER
# ==============================
log "Deploying Jaeger (all-in-one) on worker-1..."
bash "$SCRIPT_DIR/deploy-observability.sh"
tick "Jaeger deployed"

# ==============================
# STEP 6 — WAIT FOR ALL PODS
# ==============================
log "Waiting for all pods to be Ready (timeout 5 minutes)..."
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=300s \
  || fail "Pods did not become Ready within 5 minutes"
tick "All pods Ready"

# ==============================
# STEP 7 — INITIALIZE SOCIAL GRAPH
# ==============================
log "Initializing socfb-Reed98 social graph in MongoDB..."
bash "$SCRIPT_DIR/init-graph.sh"
tick "Social graph initialized"

# ==============================
# STEP 8 — VERIFY DEPLOYMENT
# ==============================
log "Verifying deployment..."
bash "$SCRIPT_DIR/verify-deployment.sh"

# ==============================
# FINAL SUMMARY
# ==============================
log "Deployment COMPLETE ✅"
NGINX_IP=$(kubectl get svc nginx-thrift -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")
ZTUNNEL_POD=$(kubectl get pods -n istio-system -o wide | awk -v node="$WORKER_0" '$0 ~ "ztunnel" && $7 == node {print $1}')
echo ""
echo "========== SUMMARY =========="
echo "Namespace:      $NAMESPACE (ambient enabled)"
echo "NGINX ClusterIP: $NGINX_IP"
echo "ztunnel (w0):  $ZTUNNEL_POD"
echo "Social Graph:  socfb-Reed98 initialized"
echo "Status:        READY FOR EXPERIMENT"
echo "============================="
