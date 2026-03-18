# Load-ramp
# Here instead of fixed load for svc-B, lets vary the load over time to create a load ramp. This will help us understand how the latency of svc-A changes as the load on svc-B increases and decreases.

# This gives load vs latency

# Above we gradually increase pressure and see how latency grows
# Below svc-a is running normally and parallely we are increasing load on svc-b in steps. This will help us understand how the latency of svc-a changes as the load on svc-b increases.

#!/bin/bash

#!/bin/bash

OUT_DIR="../results/raw/load-ramp"
mkdir -p $OUT_DIR

loads=(100 300 600 1000)

for c in "${loads[@]}"
do
  echo "Load level: $c"

  # svc-a (constant)
  kubectl exec -n mesh-exp client -- \
    wrk -t2 -c50 -d120s --latency http://svc-a.mesh-exp \
    > $OUT_DIR/svc-a_$c.txt &

  PID_A=$!

  # svc-b (increasing)
  kubectl exec -n mesh-exp client -- \
    wrk -t4 -c$c -d120s --latency http://svc-b.mesh-exp \
    > $OUT_DIR/svc-b_$c.txt &

  PID_B=$!

  wait $PID_A
  wait $PID_B
done