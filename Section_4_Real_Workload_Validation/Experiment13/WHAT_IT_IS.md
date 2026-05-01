# Experiment 13 — What Is This?

## One-Line Summary
**Noisy-neighbor interference injection into DeathStarBench via shared ztunnel contention — quantifying ztunnel CPU coupling between unrelated co-located services.**

## The Point
This experiment answers the central research question of Section 4:

> *"Does Istio Ambient Mesh create de-facto resource coupling between unrelated services that share a node's ztunnel instance, even when there is no application-level dependency between them?"*

A synthetic noisy service (`svc-noisy`) — with zero code-level coupling to DeathStarBench — is
deployed on **the same Kubernetes node** as the DSB victim services, within the same Ambient
namespace. As `svc-noisy` load increases, it generates more ztunnel mTLS work on worker-0.
That CPU contention degrades tail latency for DSB requests passing through the same ztunnel,
even though DSB itself is running at constant, sub-saturation load.

**The mechanism under study:**
```
svc-noisy traffic → ztunnel-worker0 CPU busy → DSB requests queue in ztunnel → tail latency spikes
```

---

## What Is Running

| Component | Detail |
|---|---|
| **Application (victim)** | DeathStarBench Social Network — same deployment as Experiment 12 |
| **Noisy service** | `svc-noisy` — synthetic Go HTTP server, no DSB coupling; echoes requests |
| **Noisy backend** | `svc-noisy-backend` — receives noisy traffic; co-located on worker-0 |
| **Service mesh** | **Istio Ambient Mode** — identical to Experiment 12 (same ztunnel) |
| **Namespace** | `dsb-exp` — both DSB and svc-noisy pods are in this ambient namespace |
| **mTLS** | STRICT — all svc-noisy traffic also passes through ztunnel-worker0 |
| **Kubernetes** | GKE 1.29, 3-node cluster (same as Exp11 and Exp12) |

---

## Cluster Layout

```
┌──────────────────────────────────────────────────────────────┐
│  load-gen  (default-pool-ssp-865907b54154)                   │
│  ├─ wrk2 → compose-post     50 RPS  ──────────────────────┐  │
│  ├─ wrk2 → home-timeline   100 RPS  ──────────────────────┤  │
│  ├─ wrk2 → user-timeline   100 RPS  ──────────────────────┤  │
│  └─ wrk2 → svc-noisy         N RPS  ──────────────────────┤  │
└──────────────────────────────────────────────────────────────┘
                                                              │
                                          HTTP → ztunnel HBONE│
                                                              ▼
┌──────────────────────────────────────────────────────────────┐
│  worker-0  (default-pool-ssp-11b2c93c3e14)                   │
│                                                              │
│  DSB victim-tier services (constant load):                   │
│  ├─ nginx-thrift (ingress)                                   │
│  ├─ social-graph-service  ← Case A victim                    │
│  ├─ user-service          ← Case B victim                    │
│  ├─ text-service                                             │
│  └─ media-service         ← Case C victim                    │
│                                                              │
│  Noisy services (variable load):                             │
│  ├─ svc-noisy                                                │
│  └─ svc-noisy-backend                                        │
│                                                              │
│  ████████████ ztunnel-worker0 ████████████                   │
│  (SHARED by ALL pods above — this is the contention point)   │
└──────────────────────────────────────────────────────────────┘
          │ HBONE mTLS tunnel
          ▼
┌──────────────────────────────────────────────────────────────┐
│  worker-1  (default-pool-ssp-157a7771fb89)                   │
│  ├─ home-timeline-service, post-storage-service              │
│  ├─ MongoDB x3 / Redis x2 / Jaeger                           │
│  └─ ztunnel-xyz  (separate, unaffected instance)             │
└──────────────────────────────────────────────────────────────┘
```

---

## Experimental Cases

Three placement cases vary **which DSB victim service** is co-located with the noisy pods:

| Case | Victim service pinned to worker-0 | DSB endpoints affected |
|---|---|---|
| **A** | `social-graph-service` | compose-post (heavy fan-out), home-timeline |
| **B** | `user-service` | compose-post, user-timeline |
| **C** | `media-service` | compose-post only |

> In all cases, svc-noisy and svc-noisy-backend are pinned to worker-0, sharing `ztunnel-worker0`
> with whichever DSB services are also there.

---

## Noisy Load Modes

Three injection modes characterize different real-world interference patterns:

| Mode | Traffic pattern | Peak RPS | Duration per step | What it models |
|---|---|---|---|---|
| `sustained-ramp` | Steady HTTP at 0 → 100 → 200 → ... → 700 RPS | 700 | 60 s per step | Long-running batch job or rogue microservice |
| `burst` | 200 ms @ 1500 RPS / 800 ms quiet (1 Hz cycle) | 1500 peak | 300 s total | Inbound traffic spike or retry storm |
| `churn` | 75 new connections/s + TLS renegotiation at 200 RPS | 200 steady | 300 s total | Connection-heavy workloads (short-lived RPCs) |

---

## What Is Measured

### DSB Victim Load (constant, all cases/modes)

```bash
# Three wrk2 processes in parallel — IDENTICAL to Experiment 12
wrk2 -t 2 -c 50 -d <duration>s -R 50  -T 10s --latency -s compose-post.lua  http://<nginx>:8080/wrk2-api/post/compose
wrk2 -t 2 -c 50 -d <duration>s -R 100 -T 10s --latency -s home-timeline.lua  http://<nginx>:8080/wrk2-api/home-timeline/read
wrk2 -t 2 -c 50 -d <duration>s -R 100 -T 10s --latency -s user-timeline.lua  http://<nginx>:8080/wrk2-api/user-timeline/read
```

### Noisy Load Injection (variable by mode)

```bash
# sustained-ramp: stepped RPS increase
for NOISY_RPS in 0 100 200 300 400 500 600 700; do
  wrk2 -t 4 -c 100 -d 60s -R $NOISY_RPS -T 5s http://<svc-noisy>:8080/echo &
  # ← wrk2 × 3 DSB endpoints run simultaneously
  sleep 60
done

# burst: alternating high/quiet (1 Hz)
wrk2 -t 8 -c 200 -d 300s -R 1500 --burst-mode 200ms http://<svc-noisy>:8080/echo

# churn: high connection rate at moderate RPS
wrk2 -t 4 -c 75 -d 300s -R 200 --conn-rate 75 -T 5s http://<svc-noisy>:8080/echo
```

### Metrics Collected per Trial

| Metric | How | File |
|---|---|---|
| DSB latency HdrHistogram | wrk2 `--latency` × 3 endpoints | `data/raw/<case>/<mode>/<noisy_rps>/run_NNN/<endpoint>.txt` |
| Noisy service throughput | wrk2 summary line | `data/raw/<case>/<mode>/<noisy_rps>/run_NNN/noisy-load.txt` |
| ztunnel CPU time series | Polled every 2 s | `data/raw/<case>/<mode>/<noisy_rps>/run_NNN/ztunnel-top.txt` |
| DSB pod CPU | `kubectl top pod -n dsb-exp` | `data/raw/.../pod-top.txt` |
| Node CPU | `kubectl top node` | `data/raw/.../node-top.txt` |
| Pod placement verification | `kubectl get pods -n dsb-exp -o wide` | `data/raw/.../pod-placement.txt` |
| Amplification ratio | Computed: `noisy_ms / baseline_ms` | `results/tables/amplification.csv` |

---

## Amplification Metric

The key result metric is the **amplification ratio**:

```
amplification_x = noisy_ms / baseline_ms
```

Where:
- `noisy_ms` = DSB latency percentile observed during noisy injection (from this experiment)
- `baseline_ms` = same percentile from Experiment 12 at same RPS level

Values:
- `= 1.0` → no interference
- `> 1.0` → noisy neighbor is degrading DSB latency (expected)
- `< 1.0` → impossible in a correct experiment (was a data quality issue, now corrected)

**Peak observed amplifications (Case A, sustained-ramp, 500–600 RPS noisy):**

| Endpoint | Percentile | Peak amplification |
|---|---|---|
| compose-post | P99.99 | **~4.0×** |
| home-timeline | P99 | **~5.7–9.8×** |
| home-timeline | P99.99 | **~4.8×** |
| user-timeline | P99.99 | **~2.1×** |

---

## Data Directory Structure

```
data/
└── raw/
    ├── case_A/
    │   ├── sustained_ramp/
    │   │   ├── noisy_000rps/  run_001/ {compose-post.txt, home-timeline.txt, ...}
    │   │   ├── noisy_100rps/  run_001/ ...
    │   │   └── noisy_700rps/  run_001/ ...
    │   ├── burst/
    │   │   └── run_001/ ...
    │   └── churn/
    │       └── run_001/ ...
    ├── case_B/
    └── case_C/

results/
└── tables/
    ├── amplification.csv      ← per-trial amplification ratios (primary output)
    ├── amplification_pivot.csv ← RPS × case heatmap data (compose-post P99.99)
    ├── overhead_table.csv     ← full per-mode/endpoint/metric table
    └── summary_comparison.csv ← Exp12 vs Exp13 at 700 RPS noisy
```

---

## Experiment Design

### Trial Protocol (sustained-ramp)

```
For each noisy_rps in [0, 100, 200, 300, 400, 500, 600, 700]:
  ├─ Start noisy injector at noisy_rps RPS (wrk2 against svc-noisy)
  ├─ [10 s] Warm-up / ramp-up of noisy load
  ├─ [60 s] Measurement window
  │    ├─ wrk2 × 3 DSB endpoints at constant 50/100/100 RPS
  │    ├─ ztunnel CPU polled every 2 s
  │    └─ HdrHistograms collected
  ├─ Stop noisy injector
  └─ [30 s] Cooldown before next RPS step
```

### Trial Protocol (burst / churn)

```
├─ Start noisy injector (burst/churn pattern for 300 s)
├─ [60 s] Warm-up
├─ [240 s] Measurement window
│    ├─ wrk2 × 3 DSB endpoints at constant 50/100/100 RPS
│    └─ ztunnel CPU polled every 2 s
└─ [60 s] Cooldown
```

### Full Sweep Dimensions

```
3 cases × (8 RPS steps × 1 mode + 1 burst + 1 churn) × 1–3 reps = 30–90 trials total
```

---

## How Results Are Analyzed

```bash
# Parse all wrk2 output files → amplification.csv
source .venv/bin/activate
python3 src/parse_results.py \
  --baseline ../Experiment12/results/tables/summary.csv \
  --data-dir data/raw \
  --output results/tables/amplification.csv

# Generate all comparison figures (Exp12 vs Exp13)
cd comparisons_Exp12_Exp13
bash run_comparison.sh          # 700 RPS comparison (default)
bash run_comparison.sh 500      # 500 RPS comparison

# Generate three-way figures (Exp11 vs Exp12 vs Exp13)
cd comparisons_Exp11_Exp12_Exp13
bash run_comparison_three.sh
```

The amplification CSV schema:
```csv
case,mode,noisy_rps,endpoint,metric,baseline_ms,noisy_ms,amplification_x
A,sustained-ramp,700,compose-post,p99,893.7,3560.0,3.983
A,sustained-ramp,700,home-timeline,p99_99,1000.0,4760.0,4.760
...
```

---

## Variant Sub-Experiment

The `Variant/` subdirectory contains a control experiment where `svc-noisy` is placed on
**worker-1** (a different ztunnel instance from the DSB victim services):

| | Experiment 13 | Variant |
|---|---|---|
| svc-noisy node | worker-0 (same ztunnel) | worker-1 (different ztunnel) |
| Expected result | High amplification | Near-baseline (≤ 1.2×) |
| Purpose | Show the effect | Prove ztunnel is the mechanism |

If the Variant shows no amplification at the same noisy RPS levels, it conclusively
attributes the interference to **ztunnel CPU sharing**, not general cluster load.

See `Variant/WHAT_IT_IS.md` for full details.

---

## Relationship to Other Experiments

```
Exp 11  (plain K8s — NO mesh)
   │  Δ = +8–22% added by ztunnel proxy overhead
   ▼
Exp 12  (Istio Ambient — ztunnel active, no interference)
   │  Δ = +100–535% tail latency amplification from ztunnel CPU contention
   ▼
Exp 13  (Istio Ambient + noisy pods on same ztunnel)  ← YOU ARE HERE
   │
   └─ Variant (noisy pods on different ztunnel) ← control: proves ztunnel mechanism
```

---

## Quick Commands

```bash
# One-time Python venv setup
make setup

# Verify cluster + DSB + svc-noisy are running
make verify && make noisy

# Smoke test (single trial)
bash scripts/run/run-experiment.sh --case A --mode sustained-ramp --noisy-rps 300

# Full Case A sweep (sustained-ramp 0→700)
bash scripts/run/run-sustained-ramp.sh A

# Cases B and C
bash scripts/run/run-cases-BC.sh

# Burst and churn modes
bash scripts/run/run-noisy-burst.sh A
bash scripts/run/run-noisy-churn.sh A

# Parse results → amplification.csv
make analyze

# Generate all comparison figures
make figures
```
