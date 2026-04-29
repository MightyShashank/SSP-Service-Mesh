# Experiment 13 — Noisy Neighbor Injection into DeathStarBench

> **Section 4.2 — Real Workload Validation**
> Demonstrates that co-located unrelated traffic (`svc-noisy`) causes measurable tail-latency degradation in a realistic multi-tier microservice application, attributable to shared-ztunnel interference.

---

## Overview

**Goal:** Show that `svc-noisy` (synthetic HTTP service, no DSB coupling) degrades DSB Social Network tail latency purely through shared ztunnel contention.

**Builds on:** Experiment 12 baseline (50/100/100 RPS). DSB runs at identical rates throughout — only noisy-neighbor load varies.

| Case | Victim tier pinned to worker-0 | Endpoints affected |
|------|-------------------------------|-------------------|
| **A** | social-graph-service | compose-post, home-timeline |
| **B** | user-service | compose-post, user-timeline |
| **C** | media-service | compose-post only |

| Mode | Description | Mean Load |
|------|-------------|-----------|
| `sustained-ramp` | 0 → 700 RPS in 100-step increments (60 s each) | Varies |
| `burst` | 200 ms @ 1500 RPS / 800 ms quiet, 1 Hz | ~300 RPS |
| `churn` | 75 new conns/s + TLS renegotiation at 200 RPS | 200 RPS |

**Architecture:**
```
Load generator node
  ├─ wrk2 → compose-post   50  RPS ─┐
  ├─ wrk2 → home-timeline  100 RPS ─┼─► worker-0  nginx-thrift → DSB
  ├─ wrk2 → user-timeline  100 RPS ─┘             (via ztunnel)
  └─ wrk2 → svc-noisy      N   RPS ──────────────► worker-0  svc-noisy-backend
                                                    (same ztunnel instance!)
```

---

## Complete Execution Order

All steps below are run from the **Experiment13 root directory**:
```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment13
```

---

### Step 1 — Create Python virtual environment

```bash
# Create .venv and install all dependencies (one-time setup)
bash scripts/utils/setup-venv.sh

# Activate for the current shell session
source .venv/bin/activate

# Verify
python3 -c "import matplotlib, numpy, pandas; print('[OK] venv ready')"
```

Or using Make:
```bash
make setup
make check-venv
```

> ⚠️ **Always activate the venv** before running any `python3` command:
> `source .venv/bin/activate`

---

### Step 2 — Verify cluster and DSB are running

```bash
# Confirm kubectl works
kubectl cluster-info

# All DSB pods must be Running
kubectl get pods -n dsb-exp

# Confirm social-graph is on worker-0 (Case A default placement)
kubectl get pods -n dsb-exp -o wide | grep social-graph
```

Or:
```bash
make verify
```

---

### Step 3 — Deploy svc-noisy

```bash
# Deploy the noisy-neighbor pod and its backend (both pinned to worker-0)
kubectl apply -f configs/noisy-neighbor/svc-noisy-deploy.yaml

# Wait until both pods are Ready
kubectl wait --for=condition=Ready pod -l app=svc-noisy         -n dsb-exp --timeout=120s
kubectl wait --for=condition=Ready pod -l app=svc-noisy-backend -n dsb-exp --timeout=120s

# Verify both land on worker-0
kubectl get pods -n dsb-exp -o wide | grep svc-noisy

# Confirm svc-noisy is in the ambient mesh
kubectl get namespace dsb-exp --show-labels | grep "istio.io/dataplane-mode=ambient"
```

Or:
```bash
make noisy
```

---

### Step 4 — Quick smoke test (one trial)

Verify the full pipeline works before the long sweep.

**Available Arguments for single trials:**

1. `--case` (The Victim Case — determines which service is targeted for interference on worker-0):
   * **`A`**: Targets `social-graph` (affects `compose-post` and `home-timeline`).
   * **`B`**: Targets `user-service` (affects `compose-post` and `user-timeline`).
   * **`C`**: Targets `media-service` (affects `compose-post` only).

2. `--mode` (The Noisy Neighbor Interference Pattern):
   * **`sustained-ramp`**: Consistent load generation. In a single trial, this generates a constant flat load determined by `--noisy-rps`.
   * **`burst`**: On/off spiky traffic (200ms bursts at 1500 RPS, then 800ms of quiet, repeating at 1 Hz).
   * **`churn`**: High connection turnover (75 new connections/sec with full TLS renegotiation and a steady 200 RPS payload).

3. `--noisy-rps` (The amount of interference load):
   * Accepts **any integer** value (e.g., `0`, `100`, `200`).
   * Used to set the static background RPS for the noisy neighbor when running manual `sustained-ramp` single-point trials. This flag is ignored for `burst` and `churn` modes, which use hardcoded profiles.

```bash
source .venv/bin/activate

bash scripts/run/run-experiment.sh --case A --mode sustained-ramp --noisy-rps 200

# Confirm all expected files exist in the output directory
ls data/raw/case-A/sustained-ramp/trial_001/
# Expected files:
#   compose-post.txt       ← wrk2 output (HdrHistogram + summary)
#   home-timeline.txt
#   user-timeline.txt
#   noisy-load.txt         ← wrk2 output for svc-noisy
#   ztunnel-top.txt        ← CPU / memory / thread count (every 5s)
#   pod-cpu.txt            ← kubectl top snapshot
#   run-metadata.txt       ← case, mode, noisy RPS, timestamps
#   jaeger-traces.json     ← Jaeger spans (if Jaeger is running)
```

Or:
```bash
make smoke
```

---

### Step 5 — Run Case A: Sustained Ramp (primary experiment)

Generates **Plots A, B, C, G, H**. Allow ~2 hours.
Runs 8 RPS levels (0→700, step 100) × 3 repetitions = 24 trials automatically.

```bash
source .venv/bin/activate
bash scripts/run/run-sustained-ramp.sh --case A --reps 3
# Output: data/raw/case-A/sustained-ramp/trial_001/ … trial_024/
```

Or:
```bash
make run-ramp CASE=A REPS=3
```

---

### Step 6 — Run Cases B and C (victim ordering)

Switch victim placement via Helm before each case, then run.

```bash
source .venv/bin/activate

# ── Case B: user-service victim ──────────────────────────────────────────────
# Re-pin user-service to worker-0 (edit Helm values if needed):
# helm upgrade social-network /opt/dsb/socialNetwork/helm-chart/socialnetwork -n dsb-exp \
#   --set userService.nodeSelector."role"=worker-0 \
#   --reuse-values
kubectl rollout status deployment -n dsb-exp

bash scripts/run/run-sustained-ramp.sh --case B --reps 3
# Output: data/raw/case-B/sustained-ramp/trial_*/

# ── Case C: media-service victim ─────────────────────────────────────────────
# helm upgrade social-network /opt/dsb/socialNetwork/helm-chart/socialnetwork -n dsb-exp \
#   --set mediaService.nodeSelector."role"=worker-0 \
#   --reuse-values
kubectl rollout status deployment -n dsb-exp

bash scripts/run/run-sustained-ramp.sh --case C --reps 3
# Output: data/raw/case-C/sustained-ramp/trial_*/
```

Or run both cases automatically with the convenience script (recommended):
```bash
bash scripts/run/run-cases-BC.sh --reps 3
```
This script handles the Helm re-pin, rollout wait, and ramp sweep for both Case B and Case C sequentially, in the exact order above.

Or using Make individually:
```bash
make run-ramp CASE=B REPS=3
make run-ramp CASE=C REPS=3
```

---

### Step 7 — Run Burst and Churn modes (interference mode comparison)

Restore Case A placement (social-graph on worker-0) before running.

> You only need to run Burst and Churn for Case A. There is no need to run them for Case B or Case C.

> Here is the scientific reasoning behind why the experiment is designed this way:
> 
> The Goal of Cases A, B, and C (Sustained Ramp): The purpose of doing the sustained-ramp sweep across three different cases is to prove Spatial Contention (Victim Ordering). By moving the victim around, you prove that the latency spike only happens to the specific service that shares worker-0 with the noisy neighbor.
> 
> The Goal of Burst and Churn (Case A only): The purpose of Burst and Churn is to prove Temporal Contention (Interference Patterns). You are trying to show that how the noise is generated matters. A spiky "Burst" of traffic causes worse tail latency than a smooth "Sustained" load, even if their mathematical average is the exact same.
>
> To prove that the temporal pattern matters, you only need to demonstrate it on your primary, most sensitive victim (Case A, which has social-graph-service). Running Burst and Churn on Case B and Case C would take hours of extra time just to show the exact same pattern, so it's intentionally omitted to save time without losing any scientific validity.

> (This is why Step 7 in the README explicitly tells you to "Restore Case A placement" before running it!)


```bash
source .venv/bin/activate

# ── Restore Case A placement: social-graph-service → worker-0 ─────────────────
helm upgrade social-network /opt/dsb/socialNetwork/helm-chart/socialnetwork -n dsb-exp \
  --set socialGraphService.nodeSelector."role"=worker-0 \
  --reuse-values
kubectl rollout status deployment/social-graph-service -n dsb-exp

# Verify social-graph is back on worker-0
kubectl get pods -n dsb-exp -o wide | grep social-graph

# ── Mode: Burst ───────────────────────────────────────────────────────────────
for i in 1 2 3; do
  bash scripts/run/run-experiment.sh --case A --mode burst
  sleep 120
done
# Output: data/raw/case-A/burst/trial_001/ … trial_003/

# ── Mode: Connection Churn ────────────────────────────────────────────────────
for i in 1 2 3; do
  bash scripts/run/run-experiment.sh --case A --mode churn
  sleep 120
done
# Output: data/raw/case-A/churn/trial_001/ … trial_003/
```

Or:
```bash
make run-burst CASE=A
make run-churn CASE=A
```

---

### Step 8 — Parse wrk2 outputs → CSVs

```bash
source .venv/bin/activate

for case in A B C; do
  for mode in sustained-ramp burst churn; do
    dir="data/raw/case-${case}/${mode}"
    [[ -d "$dir" ]] || continue
    echo "Parsing case-${case}/${mode}..."
    python3 src/parser/wrk2_parser.py \
      --runs-dir "$dir" \
      --output   "data/processed/csv/case-${case}/${mode}/"
  done
done

# Verify output
ls data/processed/csv/case-A/sustained-ramp/
# Expected: compose-post.csv  home-timeline.csv  user-timeline.csv
```

Or:
```bash
make parse
```

---

### Step 9 — Parse Jaeger traces → per-service latency CSVs

```bash
source .venv/bin/activate

for json_file in data/raw/case-A/sustained-ramp/trial_*/jaeger-traces.json; do
  trial_dir=$(dirname "$json_file")
  trial=$(basename "$trial_dir")
  noisy_rps=$(grep "Noisy RPS:" "$trial_dir/run-metadata.txt" | awk '{print $NF}')

  python3 src/parser/trace_parser.py \
    --input     "$json_file" \
    --output    "data/processed/csv/case-A/sustained-ramp/${trial}/traces/" \
    --label     noisy \
    --noisy-rps "${noisy_rps:-0}"
done

# Output per trial:
#   data/processed/csv/case-A/sustained-ramp/trial_001/traces/trace-summary.csv
#   data/processed/csv/case-A/sustained-ramp/trial_001/traces/spans-raw.csv
```

Or:
```bash
make parse-traces
```

---

### Step 10 — Compute amplification ratios

```bash
source .venv/bin/activate

python3 src/analysis/amplification.py \
  --baseline ../Experiment12/results/tables/summary.csv \
  --data     data/processed/csv/ \
  --output   results/tables/amplification.csv

cat results/tables/amplification.csv
```

Or:
```bash
make amplification
```

---

### Step 11 — Generate all 5 figures

```bash
source .venv/bin/activate

python3 src/plotting/plot_all.py \
  --data        results/tables/amplification.csv \
  --baseline    ../Experiment12/results/tables/summary.csv \
  --ztunnel-dir data/raw/ \
  --output      results/figures/ \
  --noisy-rps   700
```

Or (recommended):
```bash
make figures
```

> `--noisy-rps 700` sets which noisy RPS level the bar charts (Figures 2 & 5) use for
> the "with noisy load" bars. Use the highest RPS level you have data for (default: 700).
> Plots with no ztunnel-top data fall back to an informative placeholder PNG.

**Prerequisites:** Step 10 (amplification.csv) must be complete before running this step.

**Output figures:**

| Figure | File | Description |
|--------|------|-------------|
| **1 — Hero** | `throughput/hero-p9999-vs-noisy-rps.{pdf,png}` | compose-post P99.99 amplification vs noisy RPS — Case A sustained ramp |
| **2 — Victim ordering** | `victim-ordering/victim-ordering-bar.{pdf,png}` | P99.99 amplification bar chart for Cases A, B, C at 700 RPS |
| **3 — Mode comparison** | `interference-modes/interference-mode-comparison.{pdf,png}` | Sustained vs burst vs churn at matched mean load |
| **4 — ztunnel CPU** | `ztunnel-cpu/ztunnel-cpu-over-time.{pdf,png}` | ztunnel CPU utilization over time — Case A trials |
| **5 — Baseline vs noisy** | `latency-cdf/baseline-vs-noisy-bars.{pdf,png}` | P50 / P99 / P99.99 with vs without noisy load — Case A |

```
results/figures/
├── throughput/
│   └── hero-p9999-vs-noisy-rps.{pdf,png}           # Figure 1
├── victim-ordering/
│   └── victim-ordering-bar.{pdf,png}                # Figure 2
├── interference-modes/
│   └── interference-mode-comparison.{pdf,png}       # Figure 3
├── ztunnel-cpu/
│   └── ztunnel-cpu-over-time.{pdf,png}              # Figure 4
└── latency-cdf/
    └── baseline-vs-noisy-bars.{pdf,png}             # Figure 5
```

---

### Step 12 — Cross-Experiment Comparison (Exp12 vs Exp13)

Generates 3 CSV tables and 4 figures directly comparing the ambient mesh baseline
(Experiment 12) against the noisy-neighbor interference results (Experiment 13).
All outputs are written into `comparisons_Exp12_Exp13/`.

**Prerequisites:** Steps 10 and 11 must be complete (amplification.csv must exist).

```bash
# Option A — single shell script (recommended)
bash comparisons_Exp12_Exp13/run_comparison.sh       # uses 700 RPS for bar charts
bash comparisons_Exp12_Exp13/run_comparison.sh 500   # use a different noisy RPS

# Option B — run the Python script directly (from Experiment13 root)
source .venv/bin/activate
python3 comparisons_Exp12_Exp13/compare.py \
  --baseline ../Experiment12/results/tables/summary.csv \
  --amp      results/tables/amplification.csv \
  --output   comparisons_Exp12_Exp13/ \
  --noisy-rps 700
```

**Output tables:**

| Table | File | Description |
|-------|------|-------------|
| Overhead table | `tables/overhead_table.csv` | Absolute latencies side-by-side: Exp12 vs Exp13, every (case, mode, RPS, endpoint, metric) |
| Amplification pivot | `tables/amplification_pivot.csv` | Pivot: noisy_rps × Case → P99.99 amplification factor (compose-post, sustained-ramp) |
| Summary comparison | `tables/summary_comparison.csv` | Exp12 baseline vs Exp13 at fixed noisy RPS for all endpoints |

**Output figures:**

| Figure | File | Description |
|--------|------|-------------|
| Amplification curves | `figures/amplification_curves.{pdf,png}` | P99.99 amplification vs noisy RPS — all 3 cases × 3 endpoints (3-panel) |
| Percentile comparison | `figures/percentile_comparison_700rps.{pdf,png}` | Grouped bars: Exp12 vs Exp13 P50/P99/P99.99 per endpoint per case |
| Amplification heatmap | `figures/amplification_heatmap.{pdf,png}` | Colour-coded matrix: Case × noisy_rps → amplification factor |
| Mode vs baseline | `figures/mode_vs_baseline.{pdf,png}` | Sustained/burst/churn amplification curves vs Exp12 baseline |

```
comparisons_Exp12_Exp13/
├── compare.py                                      ← main script
├── run_comparison.sh                               ← one-shot runner
├── tables/
│   ├── overhead_table.csv
│   ├── amplification_pivot.csv
│   └── summary_comparison.csv
└── figures/
    ├── amplification_curves.{pdf,png}
    ├── amplification_heatmap.{pdf,png}
    ├── mode_vs_baseline.{pdf,png}
    └── percentile_comparison_700rps.{pdf,png}
```

---

## Full Workflow via Make (recommended)

```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment13

make setup          # Step 1: create .venv + install deps
make verify         # Step 2: check cluster + DSB
make noisy          # Step 3: deploy svc-noisy
make smoke          # Step 4: sanity test (1 trial)
make run-ramp CASE=A REPS=3   # Step 5: Case A sustained ramp
make run-ramp CASE=B REPS=3   # Step 6a: Case B
make run-ramp CASE=C REPS=3   # Step 6b: Case C
make run-burst CASE=A         # Step 7a: burst mode
make run-churn CASE=A         # Step 7b: churn mode
make analyze        # Steps 8–10: parse + traces + amplification
make figures        # Step 11: all 5 figures

# Step 12: cross-experiment comparison vs Experiment 12
bash comparisons_Exp12_Exp13/run_comparison.sh        # default 700 RPS noisy for bar charts
bash comparisons_Exp12_Exp13/run_comparison.sh 500    # use a different noisy RPS
```

---

## Metrics Reference

### A. End-to-End User Metrics (wrk2, auto-collected per trial)

| Metric | Source file | How parsed |
|--------|-------------|-----------|
| P50, P99, P99.9, P99.99 (ms) | `compose-post.txt` | `wrk2_parser.py` HdrHistogram |
| Achieved throughput (RPS) | `compose-post.txt` | `Requests/sec:` line |
| Goodput drop (%) | computed | `amplification.py` |

Endpoints: **compose-post** (50 RPS), **home-timeline** (100 RPS), **user-timeline** (100 RPS).

### B. Internal Service Metrics (Jaeger, 10% sampling, auto-collected)

Services traced on compose-post call chain:
`nginx-thrift` → `compose-post-service` → `social-graph-service`, `user-service`, `media-service`, `text-service`, `url-shorten-service`, `unique-id-service`, `post-storage-service`

Parsed by `trace_parser.py` → `trace-summary.csv` (P50/P95/P99/P99.9 per service) and `spans-raw.csv`.

### C. ztunnel Metrics (every 5 s, auto-collected per trial)

File: `ztunnel-top.txt` (TSV):
```
# columns: timestamp  pod_name  cpu_millicores  mem_mib  thread_count
2026-04-24T00:10:05+00:00   ztunnel-z54hp   245   48   32
```

| Column | Meaning |
|--------|---------|
| `cpu_millicores` | CPU used (1000m = 1 core = 100%) |
| `mem_mib` | Resident memory (Mi) |
| `thread_count` | OS threads in ztunnel proxy worker pool |

---

## Expected Results

| Endpoint | Baseline P99.99 | At 700 RPS noisy | Amplification | Goodput drop |
|----------|----------------|-----------------|--------------|-------------|
| compose-post | ~2,250 ms | 11,250–20,250 ms | **5–9×** | 8–18% |
| home-timeline | ~2,190 ms | 10,950–19,710 ms | **5–9×** | 5–12% |
| user-timeline | ~2,160 ms | 2,592–3,888 ms | **1.2–1.8×** *(negative control)* | <3% |

Key acceptance criteria:
- ✅ Case A shows >5× P99.99 amplification at 700 RPS noisy
- ✅ `user-timeline` in Case A shows <2× (locality-specific negative control)
- ✅ Case ordering: **A > B > C** in amplification magnitude
- ✅ Burst and churn produce disproportionately worse tail vs matched-mean sustained load

---

## Directory Layout

```
Experiment13/
├── .venv/                            ← Python virtual environment (created by make setup)
├── Makefile                          ← All targets: setup, deploy, run, analyze, figures
├── requirements.txt                  ← Python deps (matplotlib, numpy, pandas, scipy)
├── configs/
│   ├── wrk2/
│   │   ├── rates.env                 ← DSB rates (50/100/100 RPS)
│   │   ├── noisy-neighbor.lua        ← wrk2 Lua for svc-noisy
│   │   ├── compose-post.lua
│   │   ├── read-home-timeline.lua
│   │   └── read-user-timeline.lua
│   └── noisy-neighbor/
│       ├── modes.env                 ← Ramp/burst/churn parameters
│       └── svc-noisy-deploy.yaml     ← K8s Deployment+Service for svc-noisy
├── data/
│   ├── raw/case-A/sustained-ramp/trial_NNN/
│   │   ├── compose-post.txt          ← wrk2 HdrHistogram output
│   │   ├── home-timeline.txt
│   │   ├── user-timeline.txt
│   │   ├── noisy-load.txt            ← wrk2 output for svc-noisy
│   │   ├── ztunnel-top.txt           ← CPU/mem/threads time-series
│   │   ├── jaeger-traces.json        ← Per-service Jaeger spans
│   │   └── run-metadata.txt
│   └── processed/csv/                ← Parsed CSVs (wrk2 + Jaeger)
├── results/
│   ├── tables/amplification.csv      ← Amplification ratios vs Exp12
│   └── figures/                      ← 7 output figures
├── scripts/
│   ├── run/
│   │   ├── run-experiment.sh         ← Single trial runner
│   │   ├── run-sustained-ramp.sh     ← Full ramp sweep
│   │   ├── run-noisy-burst.sh        ← Burst interference driver
│   │   └── run-noisy-churn.sh        ← Churn interference driver
│   ├── metrics/
│   │   ├── capture-ztunnel-cpu-top.sh ← Auto-started (CPU/mem/threads)
│   │   └── collect-traces.sh          ← Auto-started (Jaeger)
│   ├── deploy/
│   ├── cleanup/
│   └── utils/
│       └── setup-venv.sh             ← Creates .venv
└── src/
    ├── parser/
    │   ├── wrk2_parser.py             ← Step 8 (same as Exp12, 3-decimal aware)
    │   └── trace_parser.py            ← Step 9 (Jaeger per-service latency)
    ├── analysis/
    │   └── amplification.py           ← Step 10 (amplification ratios)
    └── plotting/
        └── exp13_plots.py             ← Step 11 (all 7 figures)
```

---

## Cleanup

```bash
# Remove svc-noisy only (keep DSB running for Experiment 14)
make clean-noisy

# Full teardown (only if done with entire Section 4)
make clean
```

---

*Experiment 13 — Noisy Neighbor Injection · SSP T2 2025*
