#!/bin/bash
# Experiment 11 — Sequential run driver.
# Runs N full repetitions with cleanup+redeploy between each.
# Usage: ./run_sequential_experiments.sh [N]   (default N=5)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

N="${1:-5}"
log() { echo -e "\n[SEQ] $1"; }

log "Starting $N sequential repetitions (Experiment 11 — plain K8s)"

for i in $(seq 1 "$N"); do
  log "=== Repetition $i / $N ==="

  # Fresh deploy between runs to control DB state
  log "Cleanup + redeploy (fresh DB init)..."
  DSB_REPO="${DSB_REPO:-/opt/dsb}" bash "$ROOT_DIR/scripts/cleanup/cleanup-deploy-setup.sh"

  log "Running experiment..."
  bash "$ROOT_DIR/scripts/run/run-experiment.sh"

  if [[ "$i" -lt "$N" ]]; then
    log "Cooldown (90s before next repetition)..."
    sleep 90
  fi
done

log "All $N repetitions complete. Results in data/raw/"
