# Experiment 12 — What Is This?

## One-Line Summary
**DeathStarBench Social Network on Istio Ambient Mesh (ztunnel only, no sidecars) — the mesh-overhead baseline.**

## The Point
This is the **Istio Ambient Mesh baseline** for Section 4 of the SSP thesis.
It runs the **identical workload** as Experiment 11 (same RPS, same endpoints, same cluster topology),
but now with Istio Ambient Mode fully active. Every pod's traffic traverses the
**ztunnel DaemonSet**, which enforces transparent per-node mTLS and L4 policy.

- **Exp12 − Exp11** = pure cost of the Istio Ambient control plane and ztunnel proxy (8–22% by percentile)
- This file is consumed directly by Experiment 13 as its `baseline` when computing amplification ratios

Without this experiment, Experiment 13 cannot express its interference results as meaningful multiples.

---

## What Is Running

| Component | Detail |
|---|---|
| **Application** | DeathStarBench Social Network — 12+ microservices (nginx-thrift, social-graph-service, user-service, text-service, media-service, post-storage-service, user-timeline-service, home-timeline-service, url-shorten-service, user-mention-service, media-frontend, Jaeger, MongoDB, Redis) |
| **Social graph** | `socfb-Reed98` — 962 nodes, 18,812 edges — re-initialized once before the 5-rep block |
| **Service mesh** | **Istio Ambient Mode** — ztunnel DaemonSet (one pod per node), no sidecar proxies |
| **mTLS** | STRICT PeerAuthentication — ztunnel enforces mutual TLS for all in-namespace pod-to-pod traffic |
| **Namespace** | `dsb-exp` — labelled `istio.io/dataplane-mode: ambient` |
| **Waypoint proxy** | **None** — L7 policy not configured; only ztunnel L4 mTLS in path |
| **Tracing** | Jaeger all-in-one (100% sampling) — Zipkin/OTLP spans include ztunnel timing |
| **Kubernetes** | GKE 1.29, 3-node cluster (1 load-gen + 2 workers) |

---

## Cluster Layout

```
┌──────────────────────────────────────────────────────┐
│  load-gen  (default-pool-ssp-865907b54154)           │
│  └─ wrk2 processes (compose-post / home-tl / user-tl)│
└──────────────────────────────────────────────────────┘
          │ HTTP/1.1 → ztunnel CONNECT tunnel (mTLS)
          ▼
┌──────────────────────────────────────────────────────┐
│  worker-0  (default-pool-ssp-11b2c93c3e14)           │  ← VICTIM TIER
│  ├─ nginx-thrift (ingress)                           │
│  ├─ social-graph-service                             │
│  ├─ user-service                                     │
│  ├─ text-service / media-service                     │
│  │                                                   │
│  └─ ztunnel-z54hp  ◄──── KEY COMPONENT              │
│     (shared L4 mTLS proxy for ALL pods on worker-0)  │
└──────────────────────────────────────────────────────┘
          │ HBONE mTLS tunnel (ztunnel ↔ ztunnel)
          ▼
┌──────────────────────────────────────────────────────┐
│  worker-1  (default-pool-ssp-157a7771fb89)           │  ← DATABASE TIER
│  ├─ post-storage / user-timeline / home-tl           │
│  ├─ MongoDB x3 / Redis x2                           │
│  ├─ url-shorten / user-mention                       │
│  ├─ Jaeger all-in-one                                │
│  └─ ztunnel-xyz  (separate instance)                 │
└──────────────────────────────────────────────────────┘
```

> `ztunnel-z54hp` on **worker-0** is the critical instance in this experiment — it handles
> all inter-pod mTLS for the victim-tier services. Its CPU usage under load is the direct
> cost of Ambient mesh overhead. In Experiment 13, this same ztunnel is what gets contended.

---

## What Is Measured

### Load Profile

Three DSB endpoints driven **simultaneously** with `wrk2` (open-loop Poisson arrivals):

| Endpoint | HTTP method | Target RPS | Call depth | What it exercises |
|---|---|---|---|---|
| `/wrk2-api/post/compose` | POST | **50 RPS** | 7 downstream services | Full write fan-out through ztunnel × 7 hops |
| `/wrk2-api/home-timeline/read` | GET | **100 RPS** | 4 downstream services | Social-graph fan-out read through ztunnel |
| `/wrk2-api/user-timeline/read` | GET | **100 RPS** | 2 downstream services | Shallow personalized read through ztunnel |

Every inter-service hop crosses ztunnel twice (egress + ingress), so each request generates
**2 × N ztunnel TLS operations** where N is the call depth.

### wrk2 Invocation (per endpoint)

```bash
wrk2 \
  -t 2 \                    # 2 worker threads
  -c 50 \                   # 50 open connections
  -d 180s \                 # 180 s measurement window
  -R <target_rps> \         # open-loop Poisson rate
  -T 10s \                  # socket timeout — captures real tail latency beyond 2 s
  --latency \               # emit HdrHistogram percentile output
  -s <lua_script> \         # endpoint-specific Lua payload generator
  http://<nginx-thrift-ip>:8080/<endpoint>
```

### Metrics Collected per Run

| Metric | How | File |
|---|---|---|
| Latency HdrHistogram | `--latency` flag in wrk2 | `data/raw/run_NNN/<endpoint>.txt` |
| P50 / P75 / P90 / P95 / P99 / P99.9 / P99.99 | Parsed from wrk2 output | `data/processed/csv/<endpoint>.csv` |
| Throughput (actual RPS achieved) | wrk2 summary line | Same CSV |
| DSB pod CPU / memory | `kubectl top pod -n dsb-exp` | `data/raw/run_NNN/pod-top.txt` |
| Istio system pod CPU | `kubectl top pod -n istio-system` | `data/raw/run_NNN/ztunnel-top.txt` |
| Node CPU / memory | `kubectl top node` | `data/raw/run_NNN/node-top.txt` |
| ztunnel CPU time series | Polled every 2 s during measurement | `data/raw/run_NNN/ztunnel-timeseries.txt` |
| Pod placement | `kubectl get pods -n dsb-exp -o wide` | `data/raw/run_NNN/pod-placement.txt` |
| Jaeger distributed traces | Jaeger query API | `data/raw/run_NNN/traces/` |

---

## Experiment Design

### Repetition Protocol

```
Session start
  │
  ├─ [ONCE] Istio Ambient setup verification:
  │    kubectl get pods -n istio-system        → ztunnel DaemonSet Running
  │    kubectl get ns dsb-exp --show-labels    → istio.io/dataplane-mode=ambient
  │    kubectl exec ztunnel -- ztunnel-dump   → policy for dsb-exp namespace loaded
  │
  ├─ [ONCE] Global 60 s warmup (warms ztunnel TLS session cache + DSB caches)
  │
  └─ Repeat N=6 times:
        ├─ Run 180 s measurement window (wrk2 × 3 endpoints in parallel)
        ├─ Collect all metrics (pod-top, node-top, ztunnel-timeseries)
        └─ 90 s cooldown (ztunnel sessions drain naturally)
```

**Why 6 runs (vs 5 in Exp11)?**
The first run occasionally shows slightly elevated latency as the ztunnel connection pool
warms up. Using 6 runs and computing the **median** across all 6 is robust to 1 warm-up outlier.

### Saturation Sweep (Pre-Baseline, Run Once)

```
compose-post: 50 → 100 → 200 → 300 → 400 → 500 → 600 RPS
              (30 s per step)
```

Confirms 50 RPS is well below the ztunnel saturation point (P99 stays < 1 s up to ~200 RPS).

### Measurement Window

| Phase | Duration | Notes |
|---|---|---|
| Warmup | 60 s | Discarded — warms ztunnel TLS sessions + DSB caches |
| Measurement | 180 s | wrk2 HdrHistogram captured |
| Cooldown between reps | 90 s | ztunnel TCP connections drain; node CPU returns to idle |

---

## Key Output: `results/tables/summary.csv`

This file is the **single most important output** of Experiment 12:

```csv
endpoint,metric,n_runs,median_ms,ci_lo_ms,ci_hi_ms
compose-post,p50,6,305.0,280.4,342.3
compose-post,p99,6,893.7,873.2,942.3
compose-post,p99_99,6,1150.0,1070.0,1590.0
home-timeline,p50,6,184.6,156.1,228.2
home-timeline,p99,6,754.7,685.8,1100.0
home-timeline,p99_99,6,1000.0,974.9,1690.0
user-timeline,p50,6,151.4,134.7,183.3
user-timeline,p99,6,637.7,600.3,713.5
user-timeline,p99_99,6,904.2,855.3,1000.0
```

- **Experiment 13** loads `summary.csv` as `--baseline` to compute `amplification_x = noisy_ms / baseline_ms`
- **Comparison scripts** use it to compute Exp12 − Exp11 mesh overhead percentages

---

## How Results Are Analyzed

```bash
# Parse all wrk2 .txt files → per-run CSVs
python3 src/parse_wrk2.py --input data/raw --output data/processed/csv

# Compute median + 95% CI across 6 repetitions → summary.csv
python3 src/analyze.py --input data/processed/csv --output results/tables/summary.csv

# Generate all paper figures
python3 src/plot.py
```

The parser extracts from wrk2 HdrHistogram output (example):
```
  50.000%   305.00ms     ← P50
  99.000%   893.70ms     ← P99  (includes ztunnel mTLS overhead)
  99.990%    1.15s        ← P99.99
```

---

## Relationship to Other Experiments

```
Exp 11  (plain K8s — NO mesh)
   │  Δ = +8–22% latency overhead from Istio Ambient ztunnel
   ▼
Exp 12  (Istio Ambient — ztunnel active, no interference)  ← YOU ARE HERE
   │  Δ = +100–535% tail latency amplification from ztunnel CPU contention
   ▼
Exp 13  (Istio Ambient + noisy neighbor pods co-located on same ztunnel)
```

The measured mesh overhead (Exp12 / Exp11) by endpoint and percentile:

| Endpoint | P50 overhead | P99 overhead | P99.99 overhead |
|---|---|---|---|
| compose-post | +9.3% | +12.4% | +17.6% |
| home-timeline | +8.2% | +14.6% | +15.6% |
| user-timeline | +9.7% | +13.3% | +21.6% |

This is consistent with published Istio Ambient micro-benchmarks (~10–20% at tail percentiles).

---

## Quick Commands

```bash
# One-time setup
make setup && make deploy && make verify

# Saturation sweep (run once)
make sweep

# 6-rep baseline measurement
make run-seq N=6

# Parse + analyze → summary.csv
make analyze

# Generate all figures
make figures
```
