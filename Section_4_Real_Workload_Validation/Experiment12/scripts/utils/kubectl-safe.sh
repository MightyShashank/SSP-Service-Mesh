#!/bin/bash
# kubectl wrapper with retry logic.
# Retries kubectl commands on transient failures (connection timeouts, etc.)
#
# Usage: bash kubectl-safe.sh <kubectl args...>
# Example: bash kubectl-safe.sh get pods -n dsb-exp

set -euo pipefail

MAX_RETRIES="${KUBECTL_RETRIES:-5}"
RETRY_DELAY="${KUBECTL_RETRY_DELAY:-5}"

ATTEMPT=1
while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
  if kubectl "$@"; then
    exit 0
  fi

  echo "[WARN] kubectl failed (attempt $ATTEMPT/$MAX_RETRIES) — retrying in ${RETRY_DELAY}s..."
  sleep "$RETRY_DELAY"
  ATTEMPT=$((ATTEMPT + 1))
done

echo "[ERROR] kubectl failed after $MAX_RETRIES attempts"
exit 1
