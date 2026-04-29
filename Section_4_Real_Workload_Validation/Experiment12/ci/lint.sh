#!/bin/bash
# Lint shell and Python scripts.
# Uses shellcheck for bash and flake8/ruff for Python.
#
# Usage: bash lint.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0

echo "============================================"
echo "  Experiment 12 — Lint Check"
echo "============================================"

# ---- Shell scripts ----
echo ""
echo "--- Shellcheck ---"
if command -v shellcheck > /dev/null 2>&1; then
  SHELL_FILES=$(find "$ROOT_DIR/scripts" "$ROOT_DIR/configs" "$ROOT_DIR/ci" -name "*.sh" -type f 2>/dev/null)
  for f in $SHELL_FILES; do
    if shellcheck "$f" > /dev/null 2>&1; then
      echo "  ✔ $(basename "$f")"
    else
      echo "  ✘ $(basename "$f")"
      shellcheck "$f" 2>&1 | head -5
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  echo "  [SKIP] shellcheck not installed"
fi

# ---- Python scripts ----
echo ""
echo "--- Python lint ---"
PY_FILES=$(find "$ROOT_DIR/src" -name "*.py" -type f 2>/dev/null)

if command -v ruff > /dev/null 2>&1; then
  for f in $PY_FILES; do
    if ruff check "$f" > /dev/null 2>&1; then
      echo "  ✔ $(basename "$f")"
    else
      echo "  ✘ $(basename "$f")"
      ERRORS=$((ERRORS + 1))
    fi
  done
elif command -v flake8 > /dev/null 2>&1; then
  for f in $PY_FILES; do
    if flake8 "$f" > /dev/null 2>&1; then
      echo "  ✔ $(basename "$f")"
    else
      echo "  ✘ $(basename "$f")"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  echo "  [SKIP] ruff/flake8 not installed"
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "  ✔ All checks passed"
else
  echo "  ✘ $ERRORS file(s) have lint errors"
fi

exit $ERRORS
