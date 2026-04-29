#!/bin/bash
# Remove node labels and reset scheduling constraints.
# Does NOT remove workloads or Istio.
#
# Usage: ./cleanup-cluster.sh

set -euo pipefail

WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"
LOAD_GEN="default-pool-ssp-865907b54154"

log()  { echo -e "\n[INFO] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Removing node labels..."
for NODE in "$WORKER_0" "$WORKER_1" "$LOAD_GEN"; do
  kubectl label node "$NODE" role- exp- 2>/dev/null || true
done

tick "Node labels removed"
kubectl get nodes --show-labels
