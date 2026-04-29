#!/bin/bash
# Experiment 11 — End-to-End Deploy Script (plain Kubernetes, NO Istio)
# Runs in order:
#   1. Node labels
#   2. Plain namespace (no Istio annotations)
#   3. DSB Social-Network via Helm (no Istio sidecar/ambient injection)
#   4. Jaeger on worker-1
#   5. Wait for all pods
#   6. Initialize social graph
#   7. Verify placement

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp11"
WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"

DSB_REPO="${DSB_REPO:-/opt/dsb}"
DSB_CHART="${DSB_REPO}/socialNetwork/helm-chart/socialnetwork"
HELM_VALUES_PLAIN="$ROOT_DIR/configs/deathstarbench/social-network/base/helm-values-plain.yaml"
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
# ==============================
if [[ ! -f "$DSB_CHART/Chart.yaml" ]]; then
  log "DSB Helm chart not found (Chart.yaml missing at $DSB_CHART)"
  if [[ -d "$DSB_REPO" && ! -d "$DSB_REPO/.git" ]]; then
    log "Removing incomplete DSB directory at $DSB_REPO ..."
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
bash "$ROOT_DIR/scripts/utils/label-nodes.sh"
tick "Nodes labeled"

# ==============================
# STEP 2 — CREATE NAMESPACE (plain, NO Istio label)
# ==============================
log "Creating plain namespace (no Istio injection)..."
kubectl apply -f "$ROOT_DIR/configs/kubernetes/namespace.yaml"
tick "Namespace $NAMESPACE created (plain K8s — no Istio)"

# ==============================
# STEP 3 — DEPLOY DSB SOCIAL-NETWORK (no Istio)
# Helm values explicitly disable any Istio sidecars / annotations.
# ==============================
log "Deploying DeathStarBench Social-Network via Helm (plain K8s)..."
helm upgrade --install social-network-exp11 "$DSB_CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$HELM_VALUES_PLAIN" \
  --values "$HELM_PLACEMENT_W0" \
  --values "$HELM_PLACEMENT_W1" \
  --timeout 300s \
  --wait
tick "DSB Social-Network deployed (no Istio)"

# ==============================
# STEP 4 — DEPLOY JAEGER
# ==============================
log "Deploying Jaeger (all-in-one) on worker-1..."
bash "$SCRIPT_DIR/deploy-observability.sh"
tick "Jaeger deployed"

# ==============================
# STEP 5 — WAIT FOR ALL PODS
# ==============================
log "Waiting for all pods to be Ready (timeout 5 minutes)..."
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=300s \
  || fail "Pods did not become Ready within 5 minutes"
tick "All pods Ready"

# ==============================
# STEP 6 — INITIALIZE SOCIAL GRAPH
# ==============================
log "Initializing socfb-Reed98 social graph in MongoDB..."
bash "$SCRIPT_DIR/init-graph.sh"
tick "Social graph initialized"

# ==============================
# STEP 7 — VERIFY DEPLOYMENT
# ==============================
log "Verifying deployment..."
bash "$SCRIPT_DIR/verify-deployment.sh"

# ==============================
# FINAL SUMMARY
# ==============================
log "Deployment COMPLETE ✅"
NGINX_IP=$(kubectl get svc nginx-thrift -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")
echo ""
echo "========== SUMMARY =========="
echo "Namespace:       $NAMESPACE (plain K8s — NO Istio)"
echo "NGINX ClusterIP: $NGINX_IP"
echo "Social Graph:    socfb-Reed98 initialized"
echo "Status:          READY FOR EXPERIMENT"
echo "============================="
