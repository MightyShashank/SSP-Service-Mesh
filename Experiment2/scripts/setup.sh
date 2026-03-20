#!/bin/bash

set -e

NS=exp-2-istio

echo "Creating namespace..."
kubectl apply -f namespace/ns.yaml

echo "Deploying HTTP server..."
kubectl apply -f deploy/http-server.yaml

echo "Deploying wrk client..."
kubectl apply -f deploy/wrk-client.yaml

echo "Waiting for pods..."
kubectl wait --for=condition=Ready pod -l app=http-server -n $NS --timeout=60s || true
kubectl wait --for=condition=Ready pod -l app=wrk-client -n $NS --timeout=60s || true

echo "Pods status:"
kubectl get pods -n $NS -o wide

echo ""
echo "Checking Istio sidecar injection..."

PODS=$(kubectl get pods -n $NS -o jsonpath='{.items[*].metadata.name}')

for pod in $PODS; do
  CONTAINERS=$(kubectl get pod $pod -n $NS -o jsonpath='{.spec.containers[*].name}')
  
  if [[ "$CONTAINERS" == *"istio-proxy"* ]]; then
    echo "[INFO] Sidecar mode detected in pod: $pod"
  else
    echo "[INFO] Ambient mode (sidecarless) for pod: $pod"
  fi
done

echo ""
echo "Checking ztunnel (ambient mode)..."
kubectl get pods -n istio-system | grep ztunnel || echo "[INFO] No ztunnel found (likely sidecar mode)"