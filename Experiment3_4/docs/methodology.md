# Methodology

## Traffic Generation

Tool: `wrk`

Traffic originates from:

- Client pod inside cluster
- Same node as services

---

## Phases

### 1. Warmup
- Duration: 30–60s
- Purpose: stabilize system

---

### 2. Baseline

wrk -t2 -c50 -d120s http://svc-a.mesh-exp


Metrics recorded:

- P50 latency
- P95 latency
- P99 latency
- Throughput

---

### 3. Interference

Simultaneous load:

- svc-a → steady load
- svc-b → aggressive load

---

### 4. Load Ramp

Gradually increase svc-b load:

100 → 300 → 600 → 1000 connections.


Purpose:

- Generate load vs latency curve

---

## Metrics Collected

### Application-level (wrk)

- Latency (avg, P50, P99)
- Requests/sec

---

### System-level

- ztunnel CPU usage
- Node CPU usage
- Pod CPU usage

---

### Prometheus Metrics

- Request latency
- Throughput
- Network usage

---

## Repetition

- Each experiment repeated 3–5 times
- Results averaged

---

## Controls

- Fixed replicas
- No autoscaling
- No background workloads

## Workload Design

The experiment consists of three phases:

1. Baseline (no interference)
2. Interference (noisy neighbor introduced)
3. Load ramp (progressive stress)

All traffic is generated using wrk from a client pod running on the same node.