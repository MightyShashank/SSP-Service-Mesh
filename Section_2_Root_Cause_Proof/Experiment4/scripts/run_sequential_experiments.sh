# ./run_sequential_experiments.sh 5
# 5 is the number of experiments you are running (full cycle of all load levels + eBPF)


#!/bin/bash

set -euo pipefail

# ==============================
# INPUT
# ==============================
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <num_experiments>"
  exit 1
fi

NUM_EXPERIMENTS=$1

# ==============================
# HELPERS
# ==============================
log() {
  echo -e "\n[INFO] $1"
}

tick() {
  echo -e "\n\033[1;32m✔ $1\033[0m"
}

fail() {
  echo -e "\n[ERROR] $1"
  exit 1
}

# ==============================
# MAIN LOOP
# ==============================
log "Running $NUM_EXPERIMENTS experiments sequentially..."

for i in $(seq 1 $NUM_EXPERIMENTS)
do
  echo -e "\n======================================"
  echo "[RUN $i / $NUM_EXPERIMENTS]"
  echo "======================================"

  # 🔥 Cleanup + fresh deploy
  log "Cleaning up and setting up environment..."
  bash ./cleanup-deploy-setup.sh || fail "Cleanup failed"

  tick "Environment ready"

  # 🔥 Run experiment
  log "Running experiment $i..."
  bash ./run-experiment.sh || fail "Experiment $i failed"

  tick "Experiment $i completed"

done

# ==============================
# DONE
# ==============================
log "ALL EXPERIMENTS COMPLETED ✅"
