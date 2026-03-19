# Bring system to steady-state BEFORE measurement

#!/bin/bash

echo "[Warmup] Starting system warmup..."

# svc-a warmup
kubectl exec -n mesh-exp client -- \
  fortio load -c 50 -qps 300 -t 60s -loglevel Warning \
  http://svc-a.mesh-exp > /dev/null 2>&1

# svc-b warmup (light load)
kubectl exec -n mesh-exp client -- \
  fortio load -c 100 -qps 800 -t 60s -loglevel Warning \
  http://svc-b.mesh-exp > /dev/null 2>&1

echo "[Warmup] Completed"