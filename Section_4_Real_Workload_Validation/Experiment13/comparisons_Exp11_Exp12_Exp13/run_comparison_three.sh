#!/usr/bin/env bash
# run_comparison_three.sh — Three-way comparison: Exp11 vs Exp12 vs Exp13
# Execute from the Experiment13 root:
#   bash comparisons_Exp11_Exp12_Exp13/run_comparison_three.sh [noisy_rps]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP13_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$SCRIPT_DIR"

EXP11_CSV="$EXP13_ROOT/../Experiment11/results/tables/summary.csv"
EXP12_CSV="$EXP13_ROOT/../Experiment12/results/tables/summary.csv"
AMP13_CSV="$EXP13_ROOT/results/tables/amplification.csv"
NOISY_RPS="${1:-700}"

echo "═══════════════════════════════════════════════════════"
echo "  Three-Way Comparison: Exp11 vs Exp12 vs Exp13"
echo "  Exp11 (plain K8s) : $EXP11_CSV"
echo "  Exp12 (Ambient)   : $EXP12_CSV"
echo "  Exp13 (amplif.)   : $AMP13_CSV"
echo "  Noisy RPS         : $NOISY_RPS"
echo "  Output            : $OUT_DIR"
echo "═══════════════════════════════════════════════════════"

source "$EXP13_ROOT/.venv/bin/activate"

[[ -f "$EXP12_CSV" ]] || { echo "[ERROR] Exp12 summary not found: $EXP12_CSV"; exit 1; }
[[ -f "$AMP13_CSV" ]] || { echo "[ERROR] Exp13 amplification not found: $AMP13_CSV"; exit 1; }
[[ -f "$EXP11_CSV" ]] || { echo "[ERROR] Exp11 summary not found: $EXP11_CSV"; echo "  Run: cd Experiment11 && python3 src/parser/wrk2_parser.py && python3 src/analysis/stats.py"; exit 1; }

python3 "$SCRIPT_DIR/compare_three.py" \
    --exp11     "$EXP11_CSV" \
    --exp12     "$EXP12_CSV" \
    --amp13     "$AMP13_CSV" \
    --output    "$OUT_DIR" \
    --noisy-rps "$NOISY_RPS"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Tables:"
find "$OUT_DIR/tables" -name "*.csv" 2>/dev/null | sort | sed 's/^/    /'
echo ""
echo "  Figures:"
find "$OUT_DIR/figures" -name "*.png" 2>/dev/null | sort | sed 's/^/    /'
echo "═══════════════════════════════════════════════════════"
