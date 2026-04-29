#!/bin/bash

set -e

echo "Creating namespace..."
kubectl apply -f namespace/ns.yaml

echo "Deploying HTTP server..."
kubectl apply -f deploy/http-server.yaml

echo "Deploying wrk client..."
kubectl apply -f deploy/wrk-client.yaml

echo "Waiting for pods..."
kubectl wait --for=condition=Ready pod -l app=http-server -n exp-1-baseline --timeout=60s || true
kubectl wait --for=condition=Ready pod -l app=wrk-client -n exp-1-baseline --timeout=60s || true

kubectl get pods -n exp-1-baseline -o wide