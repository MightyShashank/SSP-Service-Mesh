#!/bin/bash
# Experiment 13 — Run Cases B and C (victim ordering).
#
# For each case, this script:
#   1. Upgrades the Helm release to re-pin the victim service to worker-0
#   2. Waits for the rollout to complete
#   3. Runs the full sustained-ramp sweep (8 RPS levels × 3 reps = 24 trials)
#
# Usage:
#   bash scripts/run/run-cases-BC.sh [--reps 3]
#
# Output:
#   data/raw/case-B/sustained-ramp/trial_*/
#   data/raw/case-C/sustained-ramp/trial_*/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

REPS=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reps) REPS="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown arg: $1"; exit 1 ;;
  esac
done

NAMESPACE="dsb-exp"
DSB_CHART="/opt/dsb/socialNetwork/helm-chart/socialnetwork"

log()  { echo -e "\n[INFO] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

[[ -f "$DSB_CHART/Chart.yaml" ]] \
  || fail "Helm chart not found at $DSB_CHART — is /opt/dsb cloned?"

# ── Case B: user-service victim ───────────────────────────────────────────────
log "Case B — Re-pinning user-service to worker-0..."
helm upgrade social-network "$DSB_CHART" \
  --namespace "$NAMESPACE" \
  --set "userService.nodeSelector.role=worker-0" \
  --reuse-values

log "Waiting for Case B rollout to complete..."
kubectl rollout status deployment -n "$NAMESPACE"
tick "Case B rollout complete"

log "Starting Case B sustained-ramp sweep (reps=${REPS})..."
bash "$SCRIPT_DIR/run-sustained-ramp.sh" --case B --reps "$REPS"
tick "Case B sweep complete → data/raw/case-B/sustained-ramp/"

# ── Case C: media-service victim ──────────────────────────────────────────────
log "Case C — Re-pinning media-service to worker-0..."
helm upgrade social-network "$DSB_CHART" \
  --namespace "$NAMESPACE" \
  --set "mediaService.nodeSelector.role=worker-0" \
  --reuse-values

log "Waiting for Case C rollout to complete..."
kubectl rollout status deployment -n "$NAMESPACE"
tick "Case C rollout complete"

log "Starting Case C sustained-ramp sweep (reps=${REPS})..."
bash "$SCRIPT_DIR/run-sustained-ramp.sh" --case C --reps "$REPS"
tick "Case C sweep complete → data/raw/case-C/sustained-ramp/"

echo ""
echo "=========================================="
echo "Cases B and C complete."
echo "  data/raw/case-B/sustained-ramp/"
echo "  data/raw/case-C/sustained-ramp/"
echo "=========================================="
