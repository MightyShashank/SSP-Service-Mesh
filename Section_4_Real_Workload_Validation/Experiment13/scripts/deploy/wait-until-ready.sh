#!/bin/bash
# Wait until all pods in dsb-exp are Running and Ready.

set -euo pipefail

NAMESPACE="dsb-exp"
TIMEOUT=300

log()  { echo -e "\n[INFO] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Waiting for all pods in $NAMESPACE to be Ready (timeout: ${TIMEOUT}s)..."

kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout="${TIMEOUT}s" \
  || fail "Some pods did not become Ready within ${TIMEOUT}s"

tick "All pods in $NAMESPACE are Ready"
kubectl get pods -n "$NAMESPACE" -o wide
