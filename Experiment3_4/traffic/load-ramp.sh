# Load-ramp
# Here instead of fixed load for svc-B, lets vary the load over time to create a load ramp. This will help us understand how the latency of svc-A changes as the load on svc-B increases and decreases.

# This gives load vs latency

# Above we gradually increase pressure and see how latency grows
# Below svc-a is running normally and parallely we are increasing load on svc-b in steps. This will help us understand how the latency of svc-a changes as the load on svc-b increases.

#!/bin/bash

set -euo pipefail

loads=(500 1000 2000 4000)

for c in "${loads[@]}"
do
  echo "Load level: $c"

  kubectl exec -n mesh-exp client -- \
    fortio load -c 50 -qps 500 -t 120s -loglevel Error \
    -json - \
    http://svc-a.mesh-exp > ../results/raw/svc-a_$c.json &

  PID_A=$!

  kubectl exec -n mesh-exp client -- \
    fortio load -c 200 -qps $c -t 120s -loglevel Error \
    -json - \
    http://svc-b.mesh-exp > ../results/raw/svc-b_$c.json &

  PID_B=$!

  wait $PID_A
  wait $PID_B
done