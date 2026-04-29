#!/bin/bash
# Full 5-run reproducibility cycle for CI validation.
# Runs: deploy → verify → 5 sequential experiments → analyze → figures.
#
# Usage: bash reproducibility-run.sh
# WARNING: This takes ~30+ minutes. Run only in CI or for full validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log()  { echo -e "\n[INFO] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

echo "============================================"
echo "  Experiment 12 — Full Reproducibility Run"
echo "============================================"

# Step 1: Deploy
log "Step 1/5: Deploying..."
bash "$ROOT_DIR/scripts/deploy/deploy-setup.sh" || fail "Deploy failed"
tick "Deploy complete"

# Step 2: Verify
log "Step 2/5: Verifying..."
bash "$ROOT_DIR/scripts/deploy/verify-deployment.sh" || fail "Verification failed"
tick "Verification passed"

# Step 3: Run 5 repetitions
log "Step 3/5: Running 5 sequential experiments..."
bash "$ROOT_DIR/scripts/run/run_sequential_experiments.sh" 5 || fail "Experiments failed"
tick "5 repetitions complete"

# Step 4: Analyze
log "Step 4/5: Analyzing results..."
python3 "$ROOT_DIR/src/parser/wrk2_parser.py" \
  --runs-dir "$ROOT_DIR/data/raw/" \
  --output "$ROOT_DIR/data/processed/csv/" || fail "Parser failed"

python3 "$ROOT_DIR/src/analysis/stats.py" \
  --input "$ROOT_DIR/data/processed/csv/" \
  --output "$ROOT_DIR/results/tables/summary.csv" || fail "Stats failed"
tick "Analysis complete"

# Step 5: Generate figures
log "Step 5/5: Generating figures..."
python3 "$ROOT_DIR/src/plotting/report_plots.py" \
  --data-dir "$ROOT_DIR/data" \
  --output-dir "$ROOT_DIR/results/figures" || fail "Plotting failed"
tick "Figures generated"

# Done
log "Full reproducibility run COMPLETE ✅"
echo "Results: $ROOT_DIR/results/"
echo "Summary: $ROOT_DIR/results/tables/summary.csv"
