# Bring system to steady-state BEFORE measurement

#!/bin/bash

echo "[Warmup] Starting system warmup..."

# svc-a warmup (light load)
kubectl exec -n mesh-exp client -- \
  fortio load -c 10 -qps 50 -t 60s -loglevel Warning \
  http://svc-a.mesh-exp > /dev/null 2>&1

# svc-b warmup (light load)
kubectl exec -n mesh-exp client -- \
  fortio load -c 20 -qps 100 -t 60s -loglevel Warning \
  http://svc-b.mesh-exp > /dev/null 2>&1

echo "[Warmup] Completed"
