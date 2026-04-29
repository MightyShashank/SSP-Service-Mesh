#!/bin/bash
# Label the three cluster nodes for deterministic pod scheduling.
# worker-0  → victim-tier DSB services (shares ztunnel with noisy neighbor in Exp 13)
# worker-1  → mid-tier DSB services (nginx, DBs, Jaeger)
# load-gen  → wrk2 load generators (cpuset-isolated)

set -euo pipefail

WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"
LOAD_GEN="default-pool-ssp-865907b54154"

log() { echo -e "\n[INFO] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

log "Checking kubectl connectivity..."
kubectl cluster-info > /dev/null || fail "kubectl not connected to cluster"

log "Labeling worker-0 (victim-tier node)..."
kubectl label node "$WORKER_0" role=worker-0 exp=dsb-victim --overwrite

log "Labeling worker-1 (mid-tier node)..."
kubectl label node "$WORKER_1" role=worker-1 exp=dsb-midtier --overwrite

log "Labeling load-gen node (wrk2 node)..."
kubectl label node "$LOAD_GEN" role=load-gen exp=dsb-loadgen --overwrite

log "Verifying labels..."
kubectl get nodes --show-labels | grep -E "ROLES|worker-0|worker-1|load-gen" || true

echo ""
echo "========== NODE LABELS APPLIED =========="
echo "worker-0 ($WORKER_0) → role=worker-0, exp=dsb-victim"
echo "worker-1 ($WORKER_1) → role=worker-1, exp=dsb-midtier"
echo "load-gen  ($LOAD_GEN) → role=load-gen, exp=dsb-loadgen"
echo "=========================================="
