#!/bin/bash

set -e

NS=exp-1-baseline
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR=results/raw/$TIMESTAMP

mkdir -p $OUT_DIR

echo "Getting server IP..."
SERVER_IP=$(kubectl get pod http-server -n $NS -o jsonpath='{.status.podIP}')

echo "Running wrk..."

kubectl exec -n $NS wrk-client -- \
wrk -t4 -c100 -d60s --latency http://$SERVER_IP:5678 \
> $OUT_DIR/wrk.txt

# 🔥 IMPORTANT FIX
echo "Waiting for Prometheus scrape..."
sleep 20

echo "Fetching Prometheus metrics..."

./scripts/fetch_metrics.sh $OUT_DIR

echo "Saved all results to $OUT_DIR"