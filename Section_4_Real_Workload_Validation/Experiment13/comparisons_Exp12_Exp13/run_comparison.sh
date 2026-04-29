#!/usr/bin/env bash
# run_comparison.sh — Run the full Exp12 vs Exp13 comparison suite.
# Execute from the Experiment13 root directory:
#   bash comparisons_Exp12_Exp13/run_comparison.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP13_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$SCRIPT_DIR"   # outputs go into comparisons_Exp12_Exp13/ itself

BASELINE="$EXP13_ROOT/../Experiment12/results/tables/summary.csv"
AMP_CSV="$EXP13_ROOT/results/tables/amplification.csv"
NOISY_RPS="${1:-700}"   # pass as first arg, default 700

echo "═══════════════════════════════════════════════════════"
echo "  Exp12 vs Exp13 Comparison Suite"
echo "  Baseline : $BASELINE"
echo "  Amp CSV  : $AMP_CSV"
echo "  Noisy RPS: $NOISY_RPS"
echo "  Output   : $OUT_DIR"
echo "═══════════════════════════════════════════════════════"

# Activate venv
source "$EXP13_ROOT/.venv/bin/activate"

# Validate inputs
[[ -f "$BASELINE" ]] || { echo "[ERROR] Baseline CSV not found: $BASELINE"; exit 1; }
[[ -f "$AMP_CSV"  ]] || { echo "[ERROR] Amplification CSV not found: $AMP_CSV"; exit 1; }

# Run
python3 "$SCRIPT_DIR/compare.py" \
    --baseline  "$BASELINE" \
    --amp       "$AMP_CSV" \
    --output    "$OUT_DIR" \
    --noisy-rps "$NOISY_RPS"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Tables:"
find "$OUT_DIR/tables" -name "*.csv" | sort | sed 's/^/    /'
echo ""
echo "  Figures:"
find "$OUT_DIR/figures" -name "*.png" | sort | sed 's/^/    /'
echo "═══════════════════════════════════════════════════════"
