#!/bin/bash
# Label cluster nodes for Experiment 12.
# Wrapper around configs/kubernetes/node-labels.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

bash "$ROOT_DIR/configs/kubernetes/node-labels.sh"
