#!/bin/bash

set -e

NS=exp-1-baseline
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR=results/raw/$TIMESTAMP

mkdir -p $OUT_DIR

echo "Getting server IP..."
SERVER_IP=$(kubectl get pod iperf-server -n $NS -o jsonpath='{.status.podIP}')

echo "Running iperf (JSON mode)..."

kubectl exec -n $NS iperf-client -- \
iperf3 -c $SERVER_IP -P 4 -t 120 -J \
> $OUT_DIR/iperf.json

echo "Saved to $OUT_DIR/iperf.json"