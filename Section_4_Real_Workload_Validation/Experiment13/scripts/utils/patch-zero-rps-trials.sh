#!/bin/bash
# Patches noisy-load.txt for trials that ran at NOISY_RPS=0.
# wrk2 rejects -R 0 and prints its help text — these files need to be
# replaced with an explicit placeholder so the parser can handle them correctly.
#
# Usage: bash scripts/utils/patch-zero-rps-trials.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PLACEHOLDER="# NOISY_RPS=0 — baseline trial, no noisy load generated"

patch_trial() {
  local trial_dir="$1"
  local file="$trial_dir/noisy-load.txt"

  if [[ ! -d "$trial_dir" ]]; then
    echo "[SKIP] Directory not found: $trial_dir"
    return
  fi

  echo "$PLACEHOLDER" > "$file"
  echo "[PATCHED] $file"
}

patch_trial "$ROOT_DIR/data/raw/case-A/sustained-ramp/trial_002"
patch_trial "$ROOT_DIR/data/raw/case-A/sustained-ramp/trial_003"
patch_trial "$ROOT_DIR/data/raw/case-A/sustained-ramp/trial_004"

echo ""
echo "Done. Verify:"
for t in trial_002 trial_003 trial_004; do
  echo "  $t/noisy-load.txt → $(cat "$ROOT_DIR/data/raw/case-A/sustained-ramp/$t/noisy-load.txt")"
done
