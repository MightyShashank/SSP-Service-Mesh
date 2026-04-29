#!/bin/bash
# Generic retry helper.
# Usage: bash retry.sh <max_retries> <delay_seconds> <command...>
# Example: bash retry.sh 5 3 curl -s http://localhost:8080/health

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <max_retries> <delay_seconds> <command...>"
  exit 1
fi

MAX_RETRIES="$1"
RETRY_DELAY="$2"
shift 2

ATTEMPT=1
while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
  if "$@"; then
    exit 0
  fi

  echo "[WARN] Command failed (attempt $ATTEMPT/$MAX_RETRIES) — retrying in ${RETRY_DELAY}s..."
  sleep "$RETRY_DELAY"
  ATTEMPT=$((ATTEMPT + 1))
done

echo "[ERROR] Command failed after $MAX_RETRIES attempts: $*"
exit 1
