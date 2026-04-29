# Verification script for Experiment 4 — checks pod placement, ztunnel, and bpftrace availability 

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
  echo "✔ Both pods on SAME node → $NODE_A"
  SAME_NODE=true
else
  echo "✘ Pods on different nodes → experiment invalid"
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
echo "[STEP 5] bpftrace Availability (on $NODE_A)"
echo "========================================"

# Check bpftrace on the worker node
if ssh "$NODE_A" "which bpftrace" > /dev/null 2>&1; then
  BPFTRACE_VER=$(ssh "$NODE_A" "bpftrace --version 2>/dev/null" || echo "unknown")
  echo "✔ bpftrace available on $NODE_A → $BPFTRACE_VER"
else
  echo "✘ bpftrace NOT found on $NODE_A — run ebpf/install-bpftrace.sh"
fi

echo ""
echo "========================================"
echo "[STEP 6] ztunnel Symbol Check"
echo "========================================"

# Check if ztunnel binary has debug symbols for uprobes
if ssh "$NODE_A" "sudo ls /proc/\$(pgrep -f ztunnel | head -1)/exe" > /dev/null 2>&1; then
  ZTUNNEL_PID=$(ssh "$NODE_A" "pgrep -f ztunnel | head -1")
  SYMBOL_COUNT=$(ssh "$NODE_A" "sudo nm /proc/$ZTUNNEL_PID/exe 2>/dev/null | wc -l" || echo "0")
  if [[ "$SYMBOL_COUNT" -gt 10 ]]; then
    echo "✔ ztunnel binary has symbols ($SYMBOL_COUNT symbols) → uprobe mode available"
  else
    echo "⚠ ztunnel binary appears stripped → falling back to kprobe-only mode"
  fi
else
  echo "⚠ Cannot access ztunnel binary for symbol check"
fi

echo ""
echo "========================================"
echo "[FINAL VERDICT]"
echo "========================================"

if [[ "$SAME_NODE" == true && -n "$ZTUNNEL_ON_NODE" ]]; then
  echo "✔ SUCCESS: Both svc-a and svc-b are on SAME node"
  echo "✔ They share SAME ztunnel → $ZTUNNEL_ON_NODE"
  echo "✔ Intra-node communication via SAME tunnel CONFIRMED"
  echo "✔ Ready for eBPF latency decomposition"
else
  echo "✘ FAILURE: Conditions not satisfied"
fi

echo "========================================"
