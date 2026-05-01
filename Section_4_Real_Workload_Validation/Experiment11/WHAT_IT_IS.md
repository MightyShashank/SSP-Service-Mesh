# Experiment 11 — What Is This?

## One-Line Summary
**DeathStarBench Social Network on plain Kubernetes — zero service mesh, zero Istio — the latency floor.**

## The Point
This is the **zero-overhead control group** for Section 4 of the SSP thesis.
Every latency number here represents what DeathStarBench costs **on its own**, with
no proxy of any kind in the data path. No ztunnel. No sidecar. No mTLS. Just raw Kubernetes.

- The delta **Exp12 − Exp11** = pure cost of deploying Istio Ambient mesh (8–22% depending on percentile)
- The delta **Exp13 − Exp12** = additional cost of ztunnel contention under noisy-neighbor load (up to 9×)

Without this experiment you cannot make a single credible overhead claim for either.

---

## What Is Running

| Component | Detail |
|---|---|
| **Application** | DeathStarBench Social Network — 12+ microservices (nginx-thrift, social-graph-service, user-service, text-service, media-service, post-storage-service, user-timeline-service, home-timeline-service, url-shorten-service, user-mention-service, media-frontend, Jaeger, MongoDB, Redis) |
| **Social graph** | `socfb-Reed98` — 962 nodes, 18,812 edges — re-initialized once before the full 5-rep block |
| **Service mesh** | **NONE** — plain Kubernetes networking (Cilium CNI, no overlay proxy) |
| **Namespace** | `dsb-exp11` — deliberately has **no** `istio.io/dataplane-mode` label |
| **Tracing** | Jaeger all-in-one (100% sampling) — plain HTTP/Thrift spans, no mTLS overhead |
| **Kubernetes** | GKE 1.29, 3-node cluster (1 load-gen + 2 workers) |

---

## Cluster Layout

```
┌──────────────────────────────────────────────────────┐
│  load-gen  (default-pool-ssp-865907b54154)           │
│  └─ wrk2 processes (compose-post / home-tl / user-tl)│
└──────────────────────────────────────────────────────┘
          │ HTTP/1.1 (no mTLS, no proxy)
          ▼
┌────────────────────────────────────────────┐
│  worker-0  (default-pool-ssp-11b2c93c3e14) │  ← VICTIM TIER
│  ├─ nginx-thrift (ingress)                 │
│  ├─ social-graph-service                   │
│  ├─ user-service                           │
│  └─ text-service / media-service           │
└────────────────────────────────────────────┘
          │ inter-service calls (plain TCP)
          ▼
┌────────────────────────────────────────────┐
│  worker-1  (default-pool-ssp-157a7771fb89) │  ← DATABASE TIER
│  ├─ post-storage / user-timeline / home-tl │
│  ├─ MongoDB x3 / Redis x2                 │
│  ├─ url-shorten / user-mention             │
│  └─ Jaeger all-in-one                      │
└────────────────────────────────────────────┘
```

> **No ztunnel here.** The absence of `ztunnel-*.txt` files in run directories is itself a data point confirming this is a clean mesh-free baseline.

---

## What Is Measured

### Load Profile

Three DSB endpoints driven **simultaneously** with `wrk2` (open-loop Poisson arrivals, exponential inter-arrival times):

| Endpoint | HTTP method | Target RPS | Call depth | What it exercises |
|---|---|---|---|---|
| `/wrk2-api/post/compose` | POST | **50 RPS** | 7 downstream services | Full write fan-out: text → user-mention → url-shorten → media → social-graph → post-storage → home-timeline-update |
| `/wrk2-api/home-timeline/read` | GET | **100 RPS** | 4 downstream services | Social-graph fan-out read: home-timeline → post-storage + social-graph |
| `/wrk2-api/user-timeline/read` | GET | **100 RPS** | 2 downstream services | Shallow personalized read: user-timeline → post-storage |

### wrk2 Invocation (per endpoint)

```bash
wrk2 \
  -t 2 \                    # 2 worker threads
  -c 50 \                   # 50 open connections
  -d 180s \                 # 180 s measurement window (after 60 s warmup discarded)
  -R <target_rps> \         # open-loop rate (Poisson)
  -T 10s \                  # socket timeout — captures real tail beyond 2 s
  --latency \               # emit HdrHistogram percentile output
  -s <lua_script> \         # endpoint-specific Lua generator
  http://<nginx-thrift-ip>:8080/<endpoint>
```

### Metrics Collected per Run

| Metric | How | File |
|---|---|---|
| Latency HdrHistogram | `--latency` flag in wrk2 | `data/raw/run_NNN/<endpoint>.txt` |
| P50 / P75 / P90 / P95 / P99 / P99.9 / P99.99 | Parsed from wrk2 output | `data/processed/csv/<endpoint>.csv` |
| Throughput (actual RPS) | wrk2 summary line | Same CSV |
| Pod CPU / memory | `kubectl top pod -n dsb-exp11` | `data/raw/run_NNN/pod-top.txt` |
| Node CPU / memory | `kubectl top node` | `data/raw/run_NNN/node-top.txt` |
| Pod placement | `kubectl get pods -n dsb-exp11 -o wide` | `data/raw/run_NNN/pod-placement.txt` |
| Jaeger traces | Jaeger query API | `data/raw/run_NNN/traces/` |

> **No `ztunnel-top.txt`** — there is no ztunnel here. This absence is verified at parse time.

---

## Experiment Design

### Repetition Protocol

```
Session start
  │
  ├─ [ONCE] Global 60 s warmup (fills MongoDB/Redis caches, JIT warms Thrift codec)
  │
  └─ Repeat N=5 times:
        ├─ Run 180 s measurement window (wrk2 × 3 endpoints in parallel)
        ├─ Collect all metrics
        └─ 90 s cooldown (pods stay warm — no teardown/redeploy between reps)
```

**Why warm pods without teardown?**
Cold-start latency spikes (JVM warm-up, MongoDB index load, Redis cold cache) contaminate
the first few seconds of each run. A single warmup followed by warm-pod repetitions gives
cleaner, more reproducible measurements than the naive redeploy-every-rep approach.

### Saturation Sweep (Pre-Baseline, Run Once)

Before the 5-rep baseline block, a saturation sweep identifies the operating point:

```
compose-post: 50 → 100 → 200 → 300 → 400 → 500 → 600 RPS
              (30 s per step, P99 recorded)
```

Result: P99 knee at ~300 RPS confirms **50 RPS is well below saturation** — the baseline
runs in the stable region where queueing latency is small.

### Measurement Window

| Phase | Duration | Notes |
|---|---|---|
| Warmup | 60 s | Data discarded, not in CSV |
| Measurement | 180 s | wrk2 `--latency` HdrHistogram output |
| Cooldown between reps | 90 s | Cluster settles, ztunnel absent |

---

## Key Outputs

| File | Contents |
|---|---|
| `results/tables/summary.csv` | Median + 95% CI for P50/P75/P90/P99/P99.9/P99.99 across 5 reps |
| `data/processed/csv/all-endpoints.csv` | Raw per-run values (5 rows × 3 endpoints) |
| `data/processed/csv/compose-post.csv` | Per-run compose-post percentiles |
| `data/processed/csv/home-timeline.csv` | Per-run home-timeline percentiles |
| `data/processed/csv/user-timeline.csv` | Per-run user-timeline percentiles |
| `results/figures/` | Latency CDF, per-endpoint box plots, saturation curve |

---

## How Results Are Analyzed

```bash
# Parse all wrk2 .txt files → per-run CSVs
python3 src/parse_wrk2.py

# Compute median + 95% CI across repetitions → summary.csv
python3 src/analyze.py

# Generate all figures
python3 src/plot.py
```

The parser extracts percentile values directly from the HdrHistogram table in wrk2 output:

```
  50.000%   279.10ms    ← P50
  75.000%   312.90ms    ← P75
  90.000%   352.40ms    ← P90
  99.000%   794.90ms    ← P99
  99.900%   947.00ms    ← P99.9
  99.990%   978.20ms    ← P99.99
```

---

## Relationship to Other Experiments

```
Exp 11  (plain K8s — NO mesh)         ← YOU ARE HERE
   │  Δ = +8–22% latency overhead added by Istio Ambient proxy
   ▼
Exp 12  (Istio Ambient — ztunnel active, no interference)
   │  Δ = +100–535% tail latency amplification from ztunnel CPU contention
   ▼
Exp 13  (Istio Ambient + noisy neighbor pods on same ztunnel)
```

---

## Quick Commands

```bash
# One-time setup
make setup && make deploy && make verify

# Saturation sweep (run once to identify operating point)
make sweep

# 5-rep baseline measurement
make run-seq N=5

# Parse + analyze
make analyze

# Generate figures
make figures
```
