# Experiment Design

## Goal
To establish **causal evidence** that tail-latency amplification in Istio Ambient Mesh originates from **queueing delays inside the shared proxy runtime (ztunnel)** by decomposing end-to-end latency using eBPF instrumentation.

---

## Design Principle

The experiment goes beyond Experiment 3 (external observation) to instrument the **internal pipeline** of the proxy:

- eBPF probes capture per-request timestamps at 5 points in the request lifecycle
- Scheduler tracepoints measure worker thread CPU occupancy
- Correlation analysis links queueing delay to execution contention

---

## Components

### Service A (VIP / latency-sensitive)
- Lightweight workload (nginx)
- Fixed traffic at 100 RPS
- Used to measure latency decomposition

### Service B (Noisy neighbor / throughput-oriented)
- Heavy workload (http-echo)
- Load ramped: 0 → 100 → 500 → 1000 RPS
- Introduces contention at shared proxy

### Client
- Generates traffic using `fortio`
- Runs on same node for consistency

### eBPF Probes
- `latency_decomp.bt` → 5-timestamp request decomposition
- `sched_occupancy.bt` → worker thread CPU occupancy
- `queue_delay.bt` → proxy scheduling/queue delay

---

## Key Constraint

All pods must:

- Belong to same namespace (ambient-enabled)
- Run on same node
- Share same ztunnel

eBPF probes run **on the worker node** with sudo privileges.

---

## Why eBPF?

Fortio (Experiment 3) measures latency from the **client perspective** — it sees a single number. eBPF breaks this into components:

- Where exactly is time spent?
- Is it network? Kernel? Proxy queueing? Execution?
- Does it correlate with CPU contention?

This provides **causal** rather than **correlational** evidence.

---

## Experiment Phases

For each load level (svc-B ∈ {0, 100, 500, 1000} RPS):

1. Start eBPF probes
2. Run Fortio traffic (svc-A fixed + svc-B variable)
3. Stop eBPF probes
4. Cooldown
5. Repeat

---

## What is being tested?

- Internal latency decomposition of the proxy pipeline
- Correlation between worker CPU occupancy and queueing delay
- Evidence of head-of-line blocking 
- CPU–latency decoupling behavior
