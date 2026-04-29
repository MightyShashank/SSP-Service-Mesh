#!/usr/bin/env bash
# setup-venv.sh — Create .venv and install all Python dependencies.
# Run once from the Experiment13 root directory.
#
# Usage:
#   bash scripts/utils/setup-venv.sh
#   source .venv/bin/activate

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

VENV_DIR="$ROOT_DIR/.venv"
PYTHON="${PYTHON:-python3}"

log()  { echo -e "\n[INFO] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

# ── Python check ──────────────────────────────────────────────────────────────
$PYTHON --version > /dev/null 2>&1 || fail "python3 not found"
log "Using: $($PYTHON --version)"

# ── Create venv ───────────────────────────────────────────────────────────────
if [[ -d "$VENV_DIR" ]]; then
  log ".venv already exists at $VENV_DIR — upgrading pip only"
else
  log "Creating .venv at $VENV_DIR..."
  $PYTHON -m venv "$VENV_DIR"
  tick ".venv created"
fi

# ── Install deps ──────────────────────────────────────────────────────────────
log "Installing requirements..."
# "$VENV_DIR/bin/pip" install --upgrade pip --quiet
"$VENV_DIR/bin/pip" install -r "$ROOT_DIR/requirements.txt"

tick "All dependencies installed"
echo ""
echo "Activate with:  source .venv/bin/activate"
echo "Verify with:    python3 -c 'import matplotlib, numpy, pandas; print(\"OK\")'"
