#!/bin/bash
# Initialize socfb-Reed98 social graph via DSB's official init script.
# Wrapper for use inside configs/ — the main init lives at scripts/deploy/init-graph.sh
#
# Usage: bash init-social-graph.sh <nginx_ip> [port]

set -euo pipefail

NGINX_IP="${1:-}"
PORT="${2:-8080}"
DSB_REPO="${DSB_REPO:-/opt/dsb}"

[[ -n "$NGINX_IP" ]] || { echo "Usage: $0 <nginx_ip> [port]"; exit 1; }

echo "[INFO] Initializing socfb-Reed98 graph (963 users, 18,812 edges)..."
echo "[INFO] NGINX: ${NGINX_IP}:${PORT}"
echo "[INFO] DSB repo: ${DSB_REPO}"

cd "${DSB_REPO}/socialNetwork"

python3 scripts/init_social_graph.py \
  --graph=socfb-Reed98 \
  --ip="${NGINX_IP}" \
  --port="${PORT}"

echo "[INFO] Social graph initialization complete ✔"
