#!/bin/bash
# Record run metadata: start/end time, config hash, git commit.
# Usage: bash timestamp-run.sh <phase_dir> <event> [extra_info]
# Events: "start", "end"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PHASE_DIR="${1:-}"
EVENT="${2:-start}"
EXTRA="${3:-}"

[[ -n "$PHASE_DIR" ]] || { echo "Usage: $0 <phase_dir> <event> [extra_info]"; exit 1; }

mkdir -p "$PHASE_DIR"

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
RUN_ID=$(date +"%Y%m%d_%H%M%S")
GIT_HASH=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "N/A")

META_FILE="$PHASE_DIR/run-metadata.txt"

if [[ "$EVENT" == "start" ]]; then
  {
    echo "Run ID: $RUN_ID"
    echo "Start: $TIMESTAMP"
    echo "Config hash: $GIT_HASH"
    echo "Hostname: $(hostname)"
    [[ -n "$EXTRA" ]] && echo "Extra: $EXTRA"
  } > "$META_FILE"
  echo "[INFO] Run started at $TIMESTAMP → $META_FILE"

elif [[ "$EVENT" == "end" ]]; then
  {
    echo "End: $TIMESTAMP"
    [[ -n "$EXTRA" ]] && echo "Extra: $EXTRA"
  } >> "$META_FILE"
  echo "[INFO] Run ended at $TIMESTAMP → $META_FILE"
fi
