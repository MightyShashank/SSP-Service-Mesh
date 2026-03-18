# Baseline traffic measurement (No interference)
# This is our baseline latency measurement without any interference. We will run a simple load test from the client to svc-a and measure the latency. This will help us understand the baseline performance of our services without any interference. 

# Above we measure:
# - p50 latency distribution
# - p95 latency distribution
# - p99 latency distribution
# - Throughput (Requests/Second)

# THIS IS OUR BASE REFERENCE

#!/bin/bash

OUTPUT="../results/raw/baseline.txt"

echo "[Baseline] Running..."

kubectl exec -n mesh-exp client -- \
  wrk -t2 -c50 -d120s --latency http://svc-a.mesh-exp \
  > $OUTPUT

echo "[Baseline] Done → $OUTPUT"