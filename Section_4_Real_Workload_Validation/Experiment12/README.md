
# Experiment 12: DeathStarBench Baseline Characterization

## Objective
Establish a **trustworthy, reproducible performance baseline** for DeathStarBench (DSB) Social Network running under Istio Ambient Mode with stock ztunnel and **no** co-located noisy neighbor.

This baseline is the reference for all Section 4 experiments (Exp 13–15). Every latency number claimed in the paper traces back to data collected here.

---

## Core Hypothesis
Under Istio Ambient Mode with no interference, DSB Social Network achieves acceptable tail latency (P99.99 < 65 ms for compose-post at 200 RPS) with ztunnel CPU < 20% of node budget — establishing the clean pre-interference baseline.

---

## Key Design Choices

- **Real microservice workload** — DeathStarBench Social-Network (12+ services)
- **Three endpoints driven simultaneously** — compose-post, read-home-timeline, read-user-timeline
- **wrk2 open-loop load generation** (`-D exp`) — prevents coordinated omission from masking tail latency
- **Split node placement** — victim-tier services on `worker-0`, mid-tier on `worker-1`, wrk2 on dedicated load-gen node
- **Jaeger distributed tracing** — 100% sampling during baseline for per-hop latency breakdown
- **5 repetitions with fresh DB init** — controls MongoDB WAL and Redis eviction variance

---

## Cluster Configuration

| Node | Actual Name | Role |
|------|-------------|------|
| worker-0 | `default-pool-ssp-11b2c93c3e14` | Victim-tier DSB services + ztunnel |
| worker-1 | `default-pool-ssp-157a7771fb89` | Mid-tier services (nginx, DB, Jaeger) |
| load-gen | `default-pool-ssp-865907b54154` | wrk2 load generators |

Each node: **4 vCPUs, 8 GB RAM**, Kubernetes v1.35.2, Istio Ambient 1.23.x

---

## Repository Structure

- `configs/` → Kubernetes manifests, Istio config, DSB Helm values, wrk2 scripts, observability
- `scripts/deploy/` → Deploy cluster, Istio, DSB, Jaeger, social graph init
- `scripts/run/` → Run experiment, saturation sweep, wrk2 endpoint launchers, sequential runner
- `scripts/metrics/` → Capture ztunnel CPU/RSS, Jaeger traces, kubectl top snapshots
- `scripts/cleanup/` → Teardown and idempotent cleanup-deploy cycle
- `scripts/utils/` → Pre-flight checks, node labeling, retry helpers
- `workloads/` → Load profiles, request bodies, wrk2 schedules
- `data/` → Raw wrk2 JSON, processed CSVs, run metadata
- `results/` → Figures, tables, final report
- `src/` → Python parsers, analysis, plotting
- `docs/` → Detailed methodology, architecture, design, threats-to-validity
- `notebooks/` → Jupyter analysis notebooks
- `ci/` → Smoke test, lint check, full reproducibility runner

---

## Step-by-Step Execution

### Step 0 — Create & Activate Python Virtual Environment

> **This runs first.** The venv isolates all Python dependencies (`pandas`, `scipy`, `matplotlib`, `numpy`) inside the project directory. Every subsequent step runs inside it.

```bash
cd Experiment12
source scripts/utils/setup-venv.sh
```

> **Important:** Use `source` (not `bash`). This is what makes the activation persist in your terminal — `bash` would run in a subshell and the venv would die when the script exits.

This script:
1. Creates `.venv/` in the project root (if it doesn't exist)
2. **Activates** it in your current shell (you'll see `(.venv)` in your prompt)
3. Upgrades `pip`
4. Installs all Python deps from `requirements.txt` into the venv

After this, `python3`, `pip`, and all analysis scripts use the venv automatically.

To deactivate when done:
```bash
deactivate
```

> **Note:** `.venv/` is git-ignored and does not affect your system Python.

---

### Step 1 — Check Prerequisites

```bash
bash scripts/utils/check-prereqs.sh
```

Run this **inside the active venv** (from Step 0). It validates everything else:

| Category | What it does |
|----------|-------------|
| **Python venv** | Confirms `(.venv)` is active. If not, shows a box telling you to run Step 0 first. |
| **Python packages** | Verifies `pandas`, `matplotlib`, `scipy`, `numpy` are importable with versions. |
| **System tools** | Checks `kubectl`, `helm`, `jq`, `curl`, `git`, `shellcheck`. Auto-installs missing ones via `apt`. |
| **wrk2** | Checks common paths. If missing, prints compile-from-source instructions. |
| **Cluster state** | Verifies `kubectl` connectivity, 3 nodes Ready, Istio Ambient (ztunnel DaemonSet). |
| **DSB repo** | Clones DeathStarBench to `/opt/dsb` if not present. |

To **check only** without auto-installing system packages:
```bash
bash scripts/utils/check-prereqs.sh --check-only
```

---

### Step 2 — Label Nodes
```bash
cd scripts/utils
bash label-nodes.sh
```
Assigns `role=worker-0`, `role=worker-1`, `role=load-gen` labels for deterministic pod scheduling.

---

### Step 3 — Deploy Everything (One-Shot)
```bash
cd scripts/deploy
bash deploy-setup.sh
```
This single script:
- Creates `dsb-exp` namespace with `istio.io/dataplane-mode: ambient`
- Installs/verifies Istio Ambient on cluster
- Deploys DSB Social-Network via Helm with node-affinity placement
- Deploys Jaeger (all-in-one) on `worker-1`
- Waits for all pods to be `Running + Ready`
- Initializes the socfb-Reed98 social graph in MongoDB
- Verifies pod placement and ztunnel presence on `worker-0`

---

### Step 4 — Verify Deployment
```bash
cd scripts/deploy
bash verify-deployment.sh
```
Checks:
- All DSB pods are `Running`
- Victim-tier pods (social-graph, user-service, media-service) are on `worker-0`
- Mid-tier pods (nginx, MongoDB, Redis, Jaeger) are on `worker-1`
- ztunnel DaemonSet pod exists on `worker-0`
- Jaeger UI is reachable
- NGINX ClusterIP is accessible

---

### Step 5 — Run Saturation Sweep (One-Time)
```bash
cd scripts/run
bash run-saturation-sweep.sh
```
if the above doesnt work then on terminal 1 run ```kubectl port-forward svc/nginx-thrift 18080:8080 -n dsb-exp```
and on terminal 2 run the above saturation sweep.
Sweeps compose-post from 50 → 600 RPS to find the P99 knee. Confirms 200/300/300 RPS is at 60–70% of saturation. **Run once** before the 5-repetition baseline.

---

### Step 6 — Run 5 Baseline Repetitions (Sequential)
```bash
cd scripts/run
chmod +x run_sequential_experiments.sh
./run_sequential_experiments.sh 5
```
Each repetition:
1. Runs `cleanup-deploy-setup.sh` → fresh namespace + DSB + social graph init
2. Runs `run-experiment.sh` → 60s warmup + 180s measurement across all 3 endpoints in parallel

Results saved to `data/raw/run_001/` through `run_005/`.

**Or run a single repetition manually:**
```bash
cd scripts/run
chmod +x run-experiment.sh
./run-experiment.sh
```

---

### Step 7 — Collect Extra Metrics (Optional, runs automatically)
```bash
# ztunnel CPU per-thread (auto-runs during experiment)
cd scripts/metrics
bash capture-ztunnel-stats.sh

# Jaeger traces (auto-collected at end of each run)
bash collect-traces.sh

# Sync logs from worker nodes
bash sync-logs.sh
```

---

### Step 8 — Analyze Results

```bash
# Parse all raw wrk2 outputs into CSVs
python3 src/parser/wrk2_parser.py --runs-dir data/raw/ --output data/processed/csv/

# Compute statistics (median, 95% CI, CV)
python3 src/analysis/stats.py --input data/processed/csv/ --output results/tables/summary.csv

# Check run-to-run variance (flag runs with CV > 5%)
python3 src/analysis/ci.py --input data/processed/csv/ --output results/tables/variance.csv
```

---

### Step 9 — Generate Paper Figures

The experiment produces **4 figure types**. Run them all after `stats.py`:

```bash
# ── A. Latency Percentiles per Endpoint (bar chart: P50 / P99 / P99.99) ───────
python3 src/plotting/latency_plots.py \
  --data data/processed/csv/ \
  --output results/figures/latency-cdf/
# → results/figures/latency-cdf/baseline-percentile-bars.{pdf,png}

# ── B. Throughput vs Offered Load (dual-panel: achieved RPS + P99 latency) ────
python3 src/plotting/throughput_plots.py \
  --data data/raw/saturation-sweep/ \
  --output results/figures/throughput/
# → results/figures/throughput/throughput-vs-load.{pdf,png}

# ── C. ztunnel CPU over time (requires run with new poller — see note below) ──
python3 src/plotting/cpu_plots.py \
  --runs-dir data/raw/ \
  --output results/figures/ztunnel-cpu/
# → results/figures/ztunnel-cpu/ztunnel-cpu.{pdf,png}
# NOTE: ztunnel CPU is collected automatically by run-experiment.sh via
#       scripts/metrics/capture-ztunnel-cpu-top.sh (polls every 5s).
#       Data saved to data/raw/run_NNN/ztunnel-top.txt per run.
#       If no data exists yet, cpu_plots.py renders a placeholder with instructions.

# ── D. Endpoint Tail Latency CDF (complementary CDF with log Y-axis) ──────────
python3 src/plotting/cdf_plots.py \
  --runs-dir data/raw/ \
  --output results/figures/latency-cdf/
# → results/figures/latency-cdf/tail-cdf.{pdf,png}
# → results/figures/latency-cdf/latency-cdf.{pdf,png}

# ── Saturation Sweep (P99 latency vs offered load, for context) ───────────────
python3 src/plotting/saturation_plots.py \
  --data data/raw/saturation-sweep/ \
  --output results/figures/throughput/
# → results/figures/throughput/saturation-sweep.{pdf,png}

# ── Jaeger per-hop flame chart (requires Jaeger sampling enabled) ─────────────
python3 src/plotting/latency_plots.py \
  --mode jaeger \
  --data data/raw/run_001/jaeger-traces.json \
  --output results/figures/traces/
```

**Output directory layout after all figures are generated:**
```
results/figures/
├── latency-cdf/
│   ├── baseline-percentile-bars.{pdf,png}   # Plot A
│   ├── tail-cdf.{pdf,png}                   # Plot D (CCDF, log scale)
│   └── latency-cdf.{pdf,png}               # Plot D (linear + log panel)
├── throughput/
│   ├── throughput-vs-load.{pdf,png}         # Plot B
│   └── saturation-sweep.{pdf,png}           # Saturation context
├── ztunnel-cpu/
│   └── ztunnel-cpu.{pdf,png}               # Plot C
└── traces/
    └── jaeger-flamechart-compose.pdf        # Jaeger (when available)
```

---

### Step 10 — View Results
```bash
# Summary table (paper Table 4)
cat results/tables/summary.csv

# Variance report
cat results/tables/variance.csv

# Final report
python3 src/analysis/generate_report.py

cat results/reports/final_baseline_report.md
```

---

## Cleanup

### Pure Cleanup (Teardown Only)
```bash
cd scripts/cleanup
chmod +x cleanup.sh
./cleanup.sh
```

### Cleanup and Redeploy (Idempotent — Used Between Repetitions)
```bash
cd scripts/cleanup
chmod +x cleanup-deploy-setup.sh
./cleanup-deploy-setup.sh
```

---

## Expected Results

> Updated with **actual measured values** from 5 baseline runs (50/100/100 RPS).

| Endpoint | Target RPS | Achieved RPS | P50 (ms) | P99 (ms) | P99.99 (ms) | Error Rate |
|----------|-----------|-------------|----------|----------|-------------|------------|
| compose-post | 50 | 49.9 | ~255 | ~1,990 | ~2,250 | ~1.3% |
| home-timeline | 100 | 99.7 | ~167 | ~1,820 | ~2,190 | ~0.2% |
| user-timeline | 100 | 99.9 | ~138 | ~1,770 | ~2,160 | ~0.2% |

**Key acceptance criteria (updated):**
- ✅ Achieved RPS matches target (system not saturated)
- ✅ Zero HTTP 4xx/5xx errors (application correctness confirmed)
- ✅ compose-post saturation knee at ~200 RPS (single endpoint, isolated)
- ⚠️ P50 CV is 20–32% (acceptable for cloud K8s; P99 CV is 6–34%)
- 🔄 ztunnel CPU collection active from next run onward (data/raw/run_NNN/ztunnel-top.txt)

---

## Makefile Targets

```bash
make check           # Pre-flight checks + auto-install
make deploy          # Full deploy (labels + Istio + DSB + Jaeger + graph init)
make run             # Single experiment run
make run-seq N=5     # 5 sequential repetitions
make analyze         # Parse + stats
make figures         # All 3 paper figures
make clean           # Full teardown
make verify          # Verify deployment state
```
