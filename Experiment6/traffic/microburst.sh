#!/bin/bash

set -euo pipefail

NAMESPACE="mesh-exp"

RESULTS_DIR="../results/raw/microburst"
RUN_ID=${RUN_TAG:-$(date +"%Y%m%d_%H%M%S")}

OUT_DIR="$RESULTS_DIR/$RUN_ID"
mkdir -p "$OUT_DIR"

SVC_A_QPS=200
SVC_A_CONN=20

SVC_B_QPS=2000
SVC_B_CONN=100

BURSTS=(1 5 10)
GAP=0.1
TOTAL=120

log() { echo -e "\n[INFO] $1"; }

for B in "${BURSTS[@]}"
do
  echo "=== BURST ${B} ms ==="

  DIR="$OUT_DIR/burst_${B}ms"
  mkdir -p "$DIR"

  # svc-a
  kubectl exec -n $NAMESPACE client -- \
    fortio load -c $SVC_A_CONN -qps $SVC_A_QPS -t ${TOTAL}s \
    -json - http://svc-a.mesh-exp > "$DIR/svc-a.json" &

  PID_A=$!

  # burst loop
  END=$((SECONDS + TOTAL))
  while [ $SECONDS -lt $END ]
  do
    kubectl exec -n $NAMESPACE client -- \
      fortio load -c $SVC_B_CONN -qps $SVC_B_QPS -t 0.01s \
      http://svc-b.mesh-exp > /dev/null 2>&1

    sleep $GAP
  done

  wait $PID_A

  echo "✔ Done ${B}ms"

  sleep 60
done

echo "✅ Microburst complete"