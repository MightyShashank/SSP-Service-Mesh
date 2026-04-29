#!/bin/bash
# Create and bootstrap the Python virtual environment for Experiment 12.
# This is the FIRST script to run — before check-prereqs.sh.
#
#  1. Creates .venv/ in the project root (if it doesn't exist)
#  2. Activates it (in the current shell via "source")
#  3. Upgrades pip
#  4. Installs all Python deps from requirements.txt
#
# Usage (MUST be sourced, not executed, so activation persists):
#   source scripts/utils/setup-venv.sh
#
# After this, your prompt shows (.venv) and all python3/pip calls
# use the project-local environment.
#
# ─── SOURCING SAFETY NOTE ────────────────────────────────────────────────────
# This script is designed to be sourced. Therefore:
#   • We do NOT use "set -euo pipefail" — that would modify your live shell
#     options and cause your terminal to exit on any error or Ctrl+C.
#   • We save and restore your shell's existing options around our work.
#   • All error paths use "return 1" (never "exit") so only this script
#     returns, not your entire shell session.
# ─────────────────────────────────────────────────────────────────────────────

# ── Guard: must be sourced, not executed ──────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo ""
  echo "  ✘ This script must be sourced, not executed directly."
  echo ""
  echo "  Run:  source scripts/utils/setup-venv.sh"
  echo "        (not: bash scripts/utils/setup-venv.sh)"
  echo ""
  exit 1
fi

# ── Save the caller's shell options so we can restore them on exit ────────────
_svenv_saved_opts=$(set +o)   # capture all current option states as a string

# Disable options that would kill the parent shell on error/interrupt
set +e +u +o pipefail 2>/dev/null || true

# ── Cleanup function — always restores shell options ─────────────────────────
_svenv_cleanup() {
  eval "$_svenv_saved_opts" 2>/dev/null || true
  unset _svenv_saved_opts
  unset -f _svenv_cleanup _svenv_abort
  trap - INT TERM 2>/dev/null || true
}

# Called on Ctrl+C — prints a friendly message but does NOT exit the shell
_svenv_abort() {
  echo ""
  echo "  [setup-venv] Interrupted — your shell session is still alive."
  echo "  The venv may be partially set up. Re-run:"
  echo "    source scripts/utils/setup-venv.sh"
  echo ""
  _svenv_cleanup
  return 1
}

trap '_svenv_abort' INT TERM

# ── Resolve paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"

_log()  { echo -e "\n[INFO] $1"; }
_tick() { echo -e "\033[1;32m  ✔ $1\033[0m"; }
_fail() { echo -e "\033[1;31m  ✘ $1\033[0m"; }

echo ""
echo "============================================"
echo "  Experiment 12 — Python Environment Setup"
echo "============================================"

# ── Step 1: Ensure python3-venv is available ──────────────────────────────────
if ! python3 -c "import venv" > /dev/null 2>&1; then
  _log "python3-venv not found — installing via apt..."
  if ! sudo apt-get update -qq > /dev/null 2>&1; then
    _fail "apt-get update failed — install python3-venv manually"
    _svenv_cleanup; return 1
  fi
  if ! sudo apt-get install -y -qq python3-venv python3-pip > /dev/null 2>&1; then
    _fail "Failed to install python3-venv — run: sudo apt install python3-venv python3-pip"
    _svenv_cleanup; return 1
  fi
  _tick "python3-venv installed"
fi

# ── Step 2: Create the venv ───────────────────────────────────────────────────
if [[ -d "$VENV_DIR" && -f "$VENV_DIR/bin/activate" ]]; then
  _tick "venv already exists at .venv/"
else
  _log "Creating Python venv at $VENV_DIR ..."
  if ! python3 -m venv "$VENV_DIR"; then
    _fail "python3 -m venv failed"
    _svenv_cleanup; return 1
  fi
  _tick "venv created at .venv/"
fi

# ── Step 3: Activate ──────────────────────────────────────────────────────────
# shellcheck disable=SC1091
if ! source "$VENV_DIR/bin/activate"; then
  _fail "Failed to activate venv at $VENV_DIR/bin/activate"
  _svenv_cleanup; return 1
fi
_tick "Activated venv  →  $(python3 --version)  →  $(which python3)"

# ── Step 4: Install dependencies ──────────────────────────────────────────────
_log "Installing Python packages from requirements.txt ..."

pip install --upgrade pip > /dev/null 2>&1 || true

# Run pip install; show only meaningful lines; grep exit 1 (no matches) is fine
pip install -r "$ROOT_DIR/requirements.txt" 2>&1 \
  | grep -E "^(Successfully|Requirement already)" \
  || true

echo ""

# ── Step 5: Verify installed packages ────────────────────────────────────────
ALL_OK=true
for PKG in pandas matplotlib scipy numpy; do
  if python3 -c "import $PKG" > /dev/null 2>&1; then
    _tick "$PKG $(python3 -c "import $PKG; print($PKG.__version__)" 2>/dev/null || echo '?')"
  else
    _fail "$PKG — import failed  (run: pip install $PKG)"
    ALL_OK=false
  fi
done

echo ""
echo "============================================"
if $ALL_OK; then
  echo -e "  \033[1;32m✔ venv ready — (.venv) is active in your shell\033[0m"
  echo ""
  echo "  Next: bash scripts/utils/check-prereqs.sh"
else
  echo -e "  \033[1;31m✘ Some packages failed — run: pip install -r requirements.txt\033[0m"
fi
echo "============================================"

# ── Restore the caller's shell options cleanly ────────────────────────────────
_svenv_cleanup

$ALL_OK && return 0 || return 1
