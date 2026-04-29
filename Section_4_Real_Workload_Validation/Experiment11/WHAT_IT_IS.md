# Experiment 11 — What Is This?

## One-Line Summary
**DeathStarBench Social Network on plain Kubernetes — zero service mesh, zero Istio.**

## The Point
This is the **control group** for Section 4.
Every latency number you see here represents what DSB costs **on its own**, with no proxy
in the data path. Any overhead you observe in Experiment 12 on top of these numbers
is the cost of Istio Ambient. Any amplification in Experiment 13 beyond Experiment 12
is the cost of ztunnel contention under noisy-neighbor load.

Without this experiment, you cannot make a single credible overhead claim.

---

## What Is Running
| Component | Detail |
|-----------|--------|
| **Workload** | DeathStarBench Social Network (12+ microservices) |
| **Social graph** | socfb-Reed98 — 963 users, ~18,800 edges (re-initialized every repetition) |
| **Service mesh** | **NONE** — plain Kubernetes, no sidecars, no ztunnel, no mTLS |
| **Namespace** | `dsb-exp11` — deliberately has no `istio.io/dataplane-mode` label |
| **Tracing** | Jaeger all-in-one, 100% sampling (plain HTTP spans, no mTLS) |

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
- `kubectl top pod` + `kubectl top node` snapshots
- Pod placement verification
- Jaeger distributed traces

**No ztunnel metrics** — there is no ztunnel here. `ztunnel-top.txt` does not exist in run directories, and that absence is itself the data point.

---

## Node Layout
```
worker-0  (default-pool-ssp-11b2c93c3e14)  ← victim-tier DSB services
worker-1  (default-pool-ssp-157a7771fb89)  ← mid-tier + databases + Jaeger
load-gen  (default-pool-ssp-865907b54154)  ← wrk2 generators only
```

---

## Experiment Design
- **5 repetitions**, fresh `helm uninstall` + redeploy + graph init between each
- **60 s warmup** (discarded) + **180 s measurement**
- Saturation sweep (compose-post, 50→600 RPS) run **once** before the 5-rep baseline
  to confirm 50 RPS is well below the P99 knee

---

## Relationship to Other Experiments

```
Exp 11  (plain K8s)     ← YOU ARE HERE — the zero-overhead baseline
   ↓ delta = Istio Ambient mesh cost
Exp 12  (Istio Ambient) ← same workload + ztunnel in data path
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
make analyze        # parse + statistics
make figures        # all 4 paper figures
```
