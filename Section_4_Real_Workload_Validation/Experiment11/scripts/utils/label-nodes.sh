#!/bin/bash
# Label cluster nodes for Experiment 11.
# Assigns: role=worker-0, role=worker-1, role=load-gen
# Identical to Experiment 12 labeling (same physical cluster).

set -euo pipefail

WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"
LOAD_GEN="default-pool-ssp-865907b54154"

log() { echo -e "\n[LABEL] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Labeling worker-0 (victim-tier DSB services)..."
kubectl label node "$WORKER_0" role=worker-0 --overwrite
tick "$WORKER_0 → role=worker-0"

log "Labeling worker-1 (mid-tier services, MongoDB, Jaeger)..."
kubectl label node "$WORKER_1" role=worker-1 --overwrite
tick "$WORKER_1 → role=worker-1"

log "Labeling load-gen node..."
kubectl label node "$LOAD_GEN" role=load-gen --overwrite
tick "$LOAD_GEN → role=load-gen"

log "Current node labels:"
kubectl get nodes --show-labels | grep -E "NAME|role="
