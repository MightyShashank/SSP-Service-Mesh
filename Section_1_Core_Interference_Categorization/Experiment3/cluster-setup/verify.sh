# Just a simple script to verify the setup of the cluster and the placement of the pods. It will check the pods in the "mesh-exp" namespace and also check for the ztunnel pods in the "istio-system" namespace.

#!/bin/bash

set -euo pipefail

NAMESPACE="mesh-exp"

echo "========================================"
echo "[STEP 1] Fetching pod details..."
echo "========================================"

# Get pod info
PODS_INFO=$(kubectl get pods -n "$NAMESPACE" -o wide)

echo "$PODS_INFO"

# Extract svc-a and svc-b node names
NODE_A=$(kubectl get pod -n "$NAMESPACE" -l app=svc-a -o jsonpath='{.items[0].spec.nodeName}')
NODE_B=$(kubectl get pod -n "$NAMESPACE" -l app=svc-b -o jsonpath='{.items[0].spec.nodeName}')

POD_A=$(kubectl get pod -n "$NAMESPACE" -l app=svc-a -o jsonpath='{.items[0].metadata.name}')
POD_B=$(kubectl get pod -n "$NAMESPACE" -l app=svc-b -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "========================================"
echo "[STEP 2] Pod Placement Analysis"
echo "========================================"

echo "svc-a pod: $POD_A → Node: $NODE_A"
echo "svc-b pod: $POD_B → Node: $NODE_B"

if [[ "$NODE_A" == "$NODE_B" ]]; then
  echo "✔ दोनों pods SAME node पर हैं → $NODE_A"
  SAME_NODE=true
else
  echo "✘ Pods different nodes पर हैं → experiment invalid"
  SAME_NODE=false
fi

echo ""
echo "========================================"
echo "[STEP 3] Fetching ztunnel pods"
echo "========================================"

ZTUNNEL_INFO=$(kubectl get pods -n istio-system -o wide | grep ztunnel || true)

echo "$ZTUNNEL_INFO"

# Find ztunnel running on that node
ZTUNNEL_ON_NODE=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$NODE_A" '$0 ~ "ztunnel" && $7 == node {print $1}')

echo ""
echo "========================================"
echo "[STEP 4] ztunnel Mapping"
echo "========================================"

if [[ -n "$ZTUNNEL_ON_NODE" ]]; then
  echo "✔ ztunnel on node $NODE_A → $ZTUNNEL_ON_NODE"
else
  echo "✘ No ztunnel found on node $NODE_A"
fi

echo ""
echo "========================================"
echo "[FINAL VERDICT]"
echo "========================================"

if [[ "$SAME_NODE" == true && -n "$ZTUNNEL_ON_NODE" ]]; then
  echo "✔ SUCCESS: Both svc-a and svc-b are on SAME node"
  echo "✔ They share SAME ztunnel → $ZTUNNEL_ON_NODE"
  echo "✔ Intra-node communication via SAME tunnel CONFIRMED"
else
  echo "✘ FAILURE: Conditions not satisfied"
fi

echo "========================================"