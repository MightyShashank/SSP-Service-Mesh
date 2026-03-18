# Here we run both svc-a and svc-b simultaneously to create interference. 

# svc-A = latency-sensitive workload (aka steady load)
# svc-B = noisy neighbor (aka aggresive load)

# Below both are running parallely (because of &)

# t = 0s → svc-a starts
# t = ~0s → svc-b starts immediately after
# t = 0–300s → BOTH running concurrently


#!/bin/bash

OUT_DIR="../results/raw/interference"
mkdir -p $OUT_DIR

echo "[Interference] Starting..."

# svc-a (latency-sensitive)
kubectl exec -n mesh-exp client -- \
  wrk -t2 -c50 -d300s --latency http://svc-a.mesh-exp \
  > $OUT_DIR/svc-a.txt &

PID_A=$!

# svc-b (noisy)
kubectl exec -n mesh-exp client -- \
  wrk -t8 -c400 -d300s --latency http://svc-b.mesh-exp \
  > $OUT_DIR/svc-b.txt &

PID_B=$!

wait $PID_A
wait $PID_B

echo "[Interference] Completed"