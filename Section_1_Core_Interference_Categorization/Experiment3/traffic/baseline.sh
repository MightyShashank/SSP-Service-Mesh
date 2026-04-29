# Baseline traffic measurement (No interference)
# This is our baseline latency measurement without any interference. We will run a simple load test from the client to svc-a and measure the latency. This will help us understand the baseline performance of our services without any interference. 

# Above we measure:
# - p50 latency distribution
# - p95 latency distribution
# - p99 latency distribution
# - Throughput (Requests/Second)

# THIS IS OUR BASE REFERENCE

#!/bin/bash

set -euo pipefail

echo "[Baseline] Running..."

kubectl exec -n mesh-exp client -- \
  fortio load -c 50 -qps 500 -t 120s -loglevel Error \
  -json - \
  http://svc-a.mesh-exp > ../results/raw/baseline_tmp.json

echo "[Baseline] Done"