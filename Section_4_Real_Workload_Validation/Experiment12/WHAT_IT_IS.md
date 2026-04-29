# Experiment 12 — What Is This?

## One-Line Summary
**DeathStarBench Social Network on Istio Ambient Mesh (ztunnel) — the mesh-overhead baseline.**

## The Point
This is the **Istio Ambient baseline** for Section 4.
It runs the **identical workload** as Experiment 11 (same RPS, same endpoints, same cluster),
but now with Istio Ambient Mode active. Every pod's traffic passes through the **ztunnel**
DaemonSet, which enforces mTLS and L4 policy transparently.

The delta between **Experiment 12 and Experiment 11** isolates the pure cost of Istio Ambient:
no application changes, no sidecar, just ztunnel in the data path.

This baseline also feeds directly into Experiment 13 — the amplification ratios in that
experiment are always expressed relative to these numbers.

---

## What Is Running
| Component | Detail |
|-----------|--------|
| **Workload** | DeathStarBench Social Network (12+ microservices) |
| **Social graph** | socfb-Reed98 — 963 users, ~18,800 edges (re-initialized every repetition) |
| **Service mesh** | **Istio Ambient Mode** — ztunnel DaemonSet on every node, no sidecars |
| **mTLS** | Enforced by ztunnel (STRICT PeerAuthentication) — fully transparent to apps |
| **Namespace** | `dsb-exp` — labelled `istio.io/dataplane-mode: ambient` |
| **Tracing** | Jaeger all-in-one, 100% sampling (spans collected via Zipkin/OTLP) |

---

## What Is Measured
Three DSB endpoints driven in parallel with **wrk2** (open-loop, exponential inter-arrival):

| Endpoint | Target RPS | What it exercises |
|----------|-----------|-------------------|
| `POST /wrk2-api/post/compose` | 50 | Full write fan-out: 7 victim-tier services |
| `GET /wrk2-api/home-timeline/read` | 100 | Fan-out read via social graph |
| `GET /wrk2-api/user-timeline/read` | 100 | Shallow personalized read |

**Metrics collected per run:**
- wrk2 HdrHistogram (P50 / P75 / P90 / P95 / P99 / P99.9 / P99.99)
- `kubectl top pod -n dsb-exp` snapshot (DSB pods)
- `kubectl top pod -n istio-system` snapshot ← **captures ztunnel CPU during load**
- `kubectl top node` snapshot (per-node total)
- ztunnel time-series CPU poller (`ztunnel-top.txt`) — samples every 2 s during measurement
- Pod placement verification
- Jaeger distributed traces (compose-post + nginx-thrift spans)

---

## Node Layout
```
worker-0  (default-pool-ssp-11b2c93c3e14)  ← victim-tier DSB services + ztunnel-z54hp
worker-1  (default-pool-ssp-157a7771fb89)  ← mid-tier + databases + Jaeger
load-gen  (default-pool-ssp-865907b54154)  ← wrk2 generators only
```

> `ztunnel-z54hp` on worker-0 is the critical ztunnel instance — all victim-tier
> traffic flows through it. Its CPU usage during load is the direct cost of ambient mTLS.

---

## Experiment Design
- **5 repetitions**, fresh `helm uninstall` + redeploy + graph init between each
- **60 s warmup** (discarded) + **180 s measurement**
- **-T 10s** wrk2 socket timeout — captures real tail latency beyond 2 s without ceiling
- Saturation sweep (compose-post, 50→600 RPS) run **once** before the 5-rep baseline
  to confirm 50 RPS is below the P99 knee

---

## Key Output: `results/tables/summary.csv`
This file is the **single most important output** of Experiment 12.
It contains the median + 95% CI for each endpoint's latency percentiles across 5 repetitions.

- Experiment 13 loads this file as its baseline when computing amplification ratios
- Experiment 11's equivalent file lets you compute the raw Istio overhead

---

## Relationship to Other Experiments

```
Exp 11  (plain K8s)     ← zero-overhead control
   ↓ delta = Istio Ambient mesh cost  ← YOU ARE HERE
Exp 12  (Istio Ambient) ← this experiment
   ↓ delta = ztunnel contention cost under noisy-neighbor load
Exp 13  (Istio Ambient + noisy pods) ← interference injection
```

---

## Quick Commands
```bash
# Full workflow
make setup && make deploy && make verify
make sweep          # saturation sweep (once)
make run-seq N=5    # 5 baseline repetitions
make analyze        # parse + statistics → results/tables/summary.csv
make figures        # all paper figures
```
