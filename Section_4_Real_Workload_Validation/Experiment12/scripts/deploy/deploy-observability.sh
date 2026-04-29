#!/bin/bash
# Deploy Jaeger all-in-one on worker-1 for distributed tracing during Experiment 12.
# Sampling rate: 100% (full trace collection during baseline).
# Memory limit: 4 GB (handles ~500 RPS total throughput).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE_OBS="observability"
WORKER_1="default-pool-ssp-157a7771fb89"

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "Creating observability namespace..."
kubectl create namespace "$NAMESPACE_OBS" --dry-run=client -o yaml | kubectl apply -f -

log "Deploying Jaeger all-in-one on worker-1..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: ${NAMESPACE_OBS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      nodeSelector:
        role: worker-1
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:1.54
        args:
        - "--memory.max-traces=500000"
        ports:
        - containerPort: 6831   # UDP - Jaeger Thrift compact
        - containerPort: 16686  # HTTP - Jaeger UI + query API
        - containerPort: 9411   # HTTP - Zipkin compatible (used by Istio)
        - containerPort: 4317   # gRPC - OTLP
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "4Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger-query
  namespace: ${NAMESPACE_OBS}
spec:
  selector:
    app: jaeger
  ports:
  - name: query-http
    port: 16686
    targetPort: 16686
  - name: zipkin
    port: 9411
    targetPort: 9411
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger-collector
  namespace: ${NAMESPACE_OBS}
spec:
  selector:
    app: jaeger
  ports:
  - name: zipkin
    port: 9411
    targetPort: 9411
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
EOF

log "Waiting for Jaeger to be Ready..."
kubectl wait --for=condition=Ready pod -l app=jaeger -n "$NAMESPACE_OBS" --timeout=120s \
  || fail "Jaeger pod not Ready within 2 minutes"

JAEGER_IP=$(kubectl get svc jaeger-query -n "$NAMESPACE_OBS" -o jsonpath='{.spec.clusterIP}')
tick "Jaeger deployed → ClusterIP: $JAEGER_IP (port 16686)"
