# Here we run both svc-a and svc-b simultaneously to create interference. 

# svc-A = latency-sensitive workload (aka steady load)
# svc-B = noisy neighbor (aka aggresive load)

# Below both are running parallely (because of &)

# t = 0s → svc-a starts
# t = ~0s → svc-b starts immediately after
# t = 0–300s → BOTH running concurrently

#!/bin/bash

set -euo pipefail

echo "[Interference] Starting..."

# svc-a
kubectl exec -n mesh-exp client -- \
  fortio load -c 50 -qps 500 -t 300s -loglevel Error \
  -json - \
  http://svc-a.mesh-exp > ../results/raw/svc-a_tmp.json &

PID_A=$!

# svc-b
kubectl exec -n mesh-exp client -- \
  fortio load -c 200 -qps 2000 -t 300s -loglevel Error \
  -json - \
  http://svc-b.mesh-exp > ../results/raw/svc-b_tmp.json &

PID_B=$!

wait $PID_A
wait $PID_B

echo "[Interference] Completed"