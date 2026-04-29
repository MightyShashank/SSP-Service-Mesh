#!/bin/bash
# Archive a completed run directory as a .tar.gz for storage/transfer.
# Usage: bash archive-run.sh <run_dir>
# Example: bash archive-run.sh data/raw/run_001

set -euo pipefail

RUN_DIR="${1:-}"
[[ -n "$RUN_DIR" ]] || { echo "Usage: $0 <run_dir>"; exit 1; }
[[ -d "$RUN_DIR" ]] || { echo "[ERROR] Directory not found: $RUN_DIR"; exit 1; }

RUN_NAME=$(basename "$RUN_DIR")
ARCHIVE="${RUN_DIR}/../${RUN_NAME}.tar.gz"

echo "[INFO] Archiving $RUN_DIR → $ARCHIVE"
tar -czf "$ARCHIVE" -C "$(dirname "$RUN_DIR")" "$RUN_NAME"

SIZE=$(du -h "$ARCHIVE" | awk '{print $1}')
echo "[INFO] Archive created: $ARCHIVE ($SIZE)"
