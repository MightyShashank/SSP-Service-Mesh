
---

# 📄 2️⃣ `docs/experiment-design.md`

```md id="exp-design"
# Experiment Design

## Goal
To analyze how Istio Ambient’s **node-level dataplane (ztunnel)** behaves under concurrent multi-service workloads.

---

## Design Principle

The experiment isolates **dataplane contention** by ensuring:

- All services run on the same node
- All traffic flows through a single ztunnel instance

---

## Components

### Service A (Latency-sensitive)
- Lightweight workload
- Receives steady traffic
- Used to measure latency impact

### Service B (Noisy neighbor)
- Heavy workload
- High concurrency traffic
- Introduces contention

### Client
- Generates traffic using `fortio`
- Runs on same node for consistency

---

## Key Constraint

All pods must:

- Belong to same namespace (ambient-enabled)
- Run on same node
- Share same ztunnel

---

## Why Same Node?

Ambient mesh uses:

- **ztunnel per node (not per pod)**

Thus:

svc-a + svc-b + client → same node → same ztunnel


This ensures:

- Shared CPU
- Shared queues
- Shared network stack

---

## Experiment Phases

1. Baseline (no interference)
2. Interference (svc-b load introduced)
3. Load ramp (increasing svc-b pressure)

---

## What is being tested?

- Impact of **shared dataplane contention**
- Tail latency behavior under load