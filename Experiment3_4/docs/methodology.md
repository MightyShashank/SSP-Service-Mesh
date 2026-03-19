# Methodology

## Traffic Generation

Tool: `Fortio`

Traffic originates from:

- Client pod inside cluster
- Same node as services

This ensures:
- No external network noise
- All traffic flows through the same **ztunnel (node-level dataplane)**

---

## Phases

### 1. Warmup
- Duration: 30–60s
- Purpose: stabilize system (connection reuse, cache warmup)

---

### 2. Baseline

fortio load -c 50 -qps 500 -t 120s http://svc-a.mesh-exp



Metrics recorded:

- P50 latency
- P90 latency
- P99 latency
- P99.9 latency
- Throughput (Actual QPS)

---

### 3. Interference

Simultaneous load:

- svc-a → steady load (fixed QPS)
- svc-b → aggressive load (high QPS)

This introduces contention at the shared **ztunnel dataplane**.

---

### 4. Load Ramp

Gradually increase svc-b load:

500 → 1000 → 2000 → 4000 QPS


Purpose:

- Generate **load vs latency curve**
- Observe tail latency amplification under increasing contention

---

## Metrics Collected

### Application-level (Fortio)

- Latency percentiles:
  - P50
  - P90
  - P99
  - P99.9
- Throughput (Actual QPS)
- Error rate

---

### System-level

- ztunnel CPU usage
- Node CPU usage
- Pod CPU usage

Collected via:

kubectl top
---

### Prometheus Metrics

- Request latency

histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket[1m]))

- Throughput

rate(istio_requests_total[1m])

- ztunnel CPU

rate(container_cpu_usage_seconds_total{pod=~"ztunnel.*"}[1m])

- Network usage

rate(container_network_transmit_bytes_total[1m])

---

---

## Repetition

- Each experiment repeated **3–5 times**
- Results averaged to reduce variability

---

## Controls

- Fixed replicas
- No autoscaling
- No background workloads
- Same node placement (enforced)
- Same namespace (ambient mesh enabled)

---

## Workload Design

The experiment consists of three phases:

1. Baseline (no interference)
2. Interference (noisy neighbor introduced)
3. Load ramp (progressive stress)

All traffic is generated using **Fortio with fixed QPS**, from a client pod running on the same node.

---

## Key Advantage of Fortio

Unlike connection-based tools, Fortio uses **QPS-controlled load generation**, ensuring:

- Deterministic and reproducible traffic
- Accurate load vs latency characterization
- Reliable tail latency (P99, P99.9) measurement