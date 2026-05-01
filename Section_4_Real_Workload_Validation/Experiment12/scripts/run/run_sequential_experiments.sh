#!/bin/bash
# Run N sequential experiment repetitions for Experiment 12.
# Each repetition: run-experiment → 90s cooldown (no teardown, no init-graph between reps)
# One warmup at session start fills all caches.
#
# Usage: ./run_sequential_experiments.sh <num_repetitions>
# Example: ./run_sequential_experiments.sh 5

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <num_repetitions>"
  echo "Example: $0 5"
  exit 1
fi

NUM_RUNS=$1

# ==============================
# HELPERS
# ==============================
log()  { echo -e "\n[INFO] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

log "Starting $NUM_RUNS sequential experiment repetitions (warm pods — no teardown)"
log "⚠ Pods stay warm between runs. One warmup at start, then 90s cooldowns only."
echo ""

# ── ONE-TIME WARMUP before all reps ───────────────────────────────────────────
# Run warmup ONCE to populate Redis/memcached caches and warm JIT.
# After this, 90s cooldowns between reps keep the cluster warm.
log "One-time warmup (all 3 endpoints at high rate — 60s)..."
bash "$ROOT_DIR/scripts/run/warmup.sh" "127.0.0.1" "60s"

# ==============================
# MAIN LOOP
# ==============================
for i in $(seq 1 $NUM_RUNS); do
  echo "======================================"
  echo "  REPETITION $i / $NUM_RUNS"
  echo "======================================"

  # Run experiment
  log "[$i/$NUM_RUNS] Running experiment..."
  bash "$ROOT_DIR/scripts/run/run-experiment.sh" \
    || fail "run-experiment failed on rep $i"
  tick "[$i/$NUM_RUNS] Experiment completed"

  # Cooldown between repetitions (skip after last)
  if [ "$i" -lt "$NUM_RUNS" ]; then
    log "Cooldown between repetitions (90s)..."
    sleep 90
  fi
done

# ==============================
# DONE
# ==============================
log "ALL $NUM_RUNS REPETITIONS COMPLETE ✅"
echo ""
echo "Results in: $ROOT_DIR/data/raw/"
echo "Next: run 'python3 src/parser/wrk2_parser.py' to parse results"
echo "Then: 'python3 src/analysis/stats.py' to compute statistics"
echo "Then: 'make figures' to generate paper figures"
