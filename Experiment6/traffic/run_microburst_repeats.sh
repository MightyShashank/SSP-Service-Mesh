#!/bin/bash

set -euo pipefail

RUNS=5

for i in $(seq 1 $RUNS)
do
  echo "===== RUN $i ====="

  export RUN_TAG="run_$i"

  bash ../scripts/cleanup-deploy-setup.sh
  bash warmup.sh
  bash microburst.sh

done

echo "✅ All runs done"