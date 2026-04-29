#!/bin/bash
# Experiment 13 — Sustained Ramp sweep runner.
#
# For a given victim case, steps svc-noisy from RAMP_START_RPS to
# RAMP_END_RPS in RAMP_STEP_RPS increments, running one measurement
# trial per load level. DSB continues at Exp12 rates throughout.
#
# Usage:
#   ./run-sustained-ramp.sh --case A [--reps 3]
#   ./run-sustained-ramp.sh --case B
#   ./run-sustained-ramp.sh --case C

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

VICTIM_CASE=""
REPS=3   # repetitions per RPS point for statistical stability

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case) VICTIM_CASE="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$VICTIM_CASE" ]] || { echo "[ERROR] --case A|B|C required"; exit 1; }

source "$ROOT_DIR/configs/noisy-neighbor/modes.env"

log() { echo -e "\n[INFO] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Starting sustained-ramp sweep: case=${VICTIM_CASE}, steps $RAMP_START_RPS→$RAMP_END_RPS RPS (step $RAMP_STEP_RPS)"
log "Repetitions per load level: $REPS"

NOISY_RPS=$RAMP_START_RPS
while [[ $NOISY_RPS -le $RAMP_END_RPS ]]; do
  log "── Noisy RPS = ${NOISY_RPS} ──"
  for rep in $(seq 1 "$REPS"); do
    log "  Rep $rep/$REPS at ${NOISY_RPS} RPS..."
    bash "$SCRIPT_DIR/run-experiment.sh" \
      --case "$VICTIM_CASE" \
      --mode sustained-ramp \
      --noisy-rps "$NOISY_RPS"
    # Cooldown between reps
    if [[ $rep -lt $REPS ]]; then
      log "  Cooldown 60s..."
      sleep 60
    fi
  done
  tick "Load level ${NOISY_RPS} RPS complete (${REPS} trials)"
  # Cooldown between steps
  log "Cooldown 120s before next RPS step..."
  sleep 120
  NOISY_RPS=$(( NOISY_RPS + RAMP_STEP_RPS ))
done

tick "Sustained-ramp sweep complete for Case ${VICTIM_CASE}"
