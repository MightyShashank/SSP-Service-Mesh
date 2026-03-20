#!/bin/bash

NS=exp-1-baseline
OUT_DIR=$1
PROM_URL="http://localhost:9090"

START=$(date -u -d "2 minutes ago" +%s)
END=$(date -u +%s)
STEP=5

echo "Fetching Prometheus metrics..."

# CPU
curl -s --get "$PROM_URL/api/v1/query_range" \
--data-urlencode 'query=sum by (pod)(rate(container_cpu_usage_seconds_total{namespace="exp-1-baseline"}[1m]))' \
--data-urlencode "start=$START" \
--data-urlencode "end=$END" \
--data-urlencode "step=$STEP" \
> $OUT_DIR/cpu.json

# TX
curl -s --get "$PROM_URL/api/v1/query_range" \
--data-urlencode 'query=sum by (pod)(rate(container_network_transmit_bytes_total{namespace="exp-1-baseline"}[1m]))' \
--data-urlencode "start=$START" \
--data-urlencode "end=$END" \
--data-urlencode "step=$STEP" \
> $OUT_DIR/tx.json

# RX
curl -s --get "$PROM_URL/api/v1/query_range" \
--data-urlencode 'query=sum by (pod)(rate(container_network_receive_bytes_total{namespace="exp-1-baseline"}[1m]))' \
--data-urlencode "start=$START" \
--data-urlencode "end=$END" \
--data-urlencode "step=$STEP" \
> $OUT_DIR/rx.json

echo "Metrics saved"