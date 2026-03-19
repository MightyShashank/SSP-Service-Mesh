#!/bin/bash

set -e

echo "Creating namespace..."
kubectl apply -f namespace/ns.yaml

echo "Deploying iperf server..."
kubectl apply -f deploy/iperf-server.yaml

echo "Deploying iperf client..."
kubectl apply -f deploy/iperf-client.yaml

echo "Waiting for pods..."
kubectl wait --for=condition=Ready pod -l app=iperf-server -n exp-1-baseline --timeout=60s || true
kubectl wait --for=condition=Ready pod -l app=iperf-client -n exp-1-baseline --timeout=60s || true

echo "Pods:"
kubectl get pods -n exp-1-baseline -o wide