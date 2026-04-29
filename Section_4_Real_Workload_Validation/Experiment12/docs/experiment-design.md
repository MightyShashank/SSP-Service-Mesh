# Experiment Design — Experiment 12: DeathStarBench Baseline

## Goal

Establish a **trustworthy performance baseline** for DeathStarBench Social Network running under Istio Ambient Mode with stock ztunnel and **no** co-located noisy neighbor.

This is the reference data point for all Section 4 interference experiments (Exp 13–15). Without a rigorous baseline, any interference claim is unfalsifiable.

---

## Design Principle

The experiment isolates **clean ambient mesh performance** by ensuring:

- All DSB services are deployed with correct node-affinity placement
- No noisy neighbor (`svc-noisy`) is present on `worker-0`
- wrk2 runs in open-loop mode (`-D exp`) to prevent coordinated omission
- 5 repetitions with fresh database initialization to control run-to-run variance

---

## Components

### Victim-Tier Services (worker-0)
- `social-graph-service` — Follower graph lookups, hottest path in read-home-timeline
- `user-service` — User metadata, called by compose-post and read-user-timeline
- `media-service` — Media upload handling, payload-heavy
- `url-shorten-service` — URL encoding for compose-post
- `text-filter-service` — Text processing for compose-post

These are the services that will be victimized by the noisy neighbor in Exp 13. Their baseline latency is established here.

### Mid-Tier Services (worker-1)
- `nginx-frontend` — Entry point for all wrk2 traffic
- `compose-post-service` — Orchestrates the write fan-out
- `post-storage-service` — Persists posts to MongoDB
- `home-timeline-service` — Serves cached timelines
- `user-timeline-service` — Serves user-specific timelines
- `MongoDB ×3` — Persistent storage
- `Redis ×2` — Timeline caching
- `Jaeger` — Distributed tracing collector

### Load Generator (load-gen node)
- `wrk2` (3 instances, one per DSB endpoint)
- `cpuset`-isolated to avoid interfering with Kubernetes system processes
- Open-loop mode (`-D exp`): inter-arrival times are exponentially distributed → no coordinated omission

---

## Key Constraint

All victim-tier pods must:
- Be in `dsb-exp` namespace (ambient-enabled with `istio.io/dataplane-mode: ambient`)
- Run on `worker-0` (enforced via `nodeAffinity`)
- Share the same ztunnel DaemonSet instance

wrk2 pods must:
- Run on `load-gen` node (enforced via `nodeAffinity`)
- Be `cpuset`-isolated to dedicated cores

---

## Why Split Placement?

The paper's interference model requires that:
- Victim-tier services and the noisy neighbor share the **same ztunnel instance** → hence same `worker-0`
- Mid-tier services (nginx, DBs) are on a separate node to avoid conflating their resource usage with the interference signal

If all DSB services were on the same node, ztunnel would carry both victim-tier traffic AND mid-tier traffic, making it impossible to isolate which service's tasks are in the queue.

---

## Why wrk2 (not Fortio)?

| Property | Fortio | wrk2 |
|----------|--------|------|
| Load model | QPS-controlled | Open-loop (`-D exp`) |
| Coordinated omission | Present (closed-loop) | Eliminated (`-D exp`) |
| Latency accuracy at tail | May underestimate P99.99 | Accurate at all percentiles |
| DSB community standard | No | Yes (used by Rajomon, Sinan, FIRM) |

wrk2's `-D exp` mode generates exponentially distributed inter-arrival times: true open-loop Poisson traffic. This avoids coordinated omission where a slow response causes the next request to be delayed, artificially reducing measured tail latency.

---

## Experiment Phases

### Phase 1: Saturation Sweep (Run Once)
- Sweep compose-post from 50 → 600 RPS in 50 RPS steps
- Identify P99 knee: point where P99 begins rising sharply
- Confirm 200/300/300 RPS is at 60–70% of saturation
- Purpose: defend against "your rates are too low" criticism

### Phase 2: Warmup (Per Repetition)
- Duration: 60 seconds
- All 3 endpoints at target RPS
- Discarded from analysis
- Purpose: JIT compilation, connection pool warm-up, Redis cache warm-up, MongoDB index loading

### Phase 3: Measurement (Per Repetition)
- Duration: 180 seconds
- All 3 endpoints simultaneously at 200/300/300 RPS
- Background: ztunnel CPU + RSS polling, Jaeger trace collection
- Output: wrk2 JSON + system metrics per run

### Phase 4: Database Re-initialization (Between Repetitions)
- Tear down DSB namespace → redeploy → re-run `init_social_graph.py`
- Ensures MongoDB WAL and Redis state are identical across repetitions
- Critical for reproducibility: DSB variance comes from DB state, not the network

---

## What Is Being Measured?

### Primary Metrics
- **End-to-end latency** at the wrk2 load generator: P50, P95, P99, P99.9, P99.99 per endpoint
- **Goodput** (successful RPS) and **error rate** (%) per endpoint

### Secondary Metrics
- **ztunnel CPU utilization**: per-thread, per-second from `/proc/{pid}/task/{tid}/stat`
- **ztunnel RSS**: via `/proc/{pid}/smaps_rollup`
- **Per-hop Jaeger span latency**: for compose-post call chain (flame chart)
- **Network throughput** on worker-0: nethogs per-pod

### Statistical Protocol
- 5 independent repetitions
- Report: median across repetitions for all percentiles
- 95% CI: bootstrap resampling (N=10,000)
- Validity gate: CV < 5% on P50 for all endpoints; flag and repeat failing runs

---

## Graphs to Produce

1. **Latency-Throughput Sweep** — P99 vs offered load (RPS) for each endpoint. Shows saturation knee. Defends operating point choice.
2. **Latency CDF (log-x)** — compose-post end-to-end latency at 200 RPS: three lines (No Mesh, Istio Sidecar, Istio Ambient). Shows baseline mesh overhead.
3. **Jaeger Flame Chart** — Mean per-hop latency for compose-post at baseline. Shows no single hop dominates (balanced call chain under no interference).
