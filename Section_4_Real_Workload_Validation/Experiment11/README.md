
# Experiment 11: DeathStarBench Baseline — Plain Kubernetes (No Service Mesh)

## Objective
Establish a **trustworthy, reproducible performance baseline** for DeathStarBench (DSB) Social Network running on **plain Kubernetes with no service mesh** (no Istio, no ztunnel, no sidecar proxies).

This baseline is the **mesh-free control** for Section 4 experiments. By running exactly the same workload under the same DSB deployment — minus the Istio data plane — we can **isolate and quantify the overhead introduced by Istio Ambient Mode** (Experiment 12) and attribute the noisy-neighbor tail-latency amplification seen in Experiment 13 to shared ztunnel contention rather than to general cluster load.

Every latency number claimed about mesh overhead traces back to data collected here.

---

## Core Hypothesis
On plain Kubernetes with no service mesh, DSB Social Network achieves **lower and more stable tail latency** than Experiment 12 (Istio Ambient Mode) at the same offered load (50/100/100 RPS), because there is **no ztunnel proxy** in the data path adding per-packet overhead.

---

## Relationship to Other Experiments

| Experiment | Service Mesh | Purpose |
|------------|-------------|---------|
| **Exp 11 (this)** | **None (plain K8s)** | **Mesh-free baseline — control group** |
| Exp 12 | Istio Ambient (ztunnel) | Ambient mesh baseline |
| Exp 13 | Istio Ambient (ztunnel) | Noisy-neighbor injection |

The delta between Experiment 11 and Experiment 12 is the **cost of the mesh itself** — independent of any noisy neighbor.

---

## Key Design Choices

- **Real microservice workload** — DeathStarBench Social-Network (12+ services)
- **Three endpoints driven simultaneously** — compose-post, read-home-timeline, read-user-timeline
- **wrk2 open-loop load generation** (`-D exp`) — prevents coordinated omission from masking tail latency
- **Identical offered load to Experiment 12** — 50/100/100 RPS (compose-post / home-timeline / user-timeline)
- **Same split node placement** — victim-tier services on `worker-0`, mid-tier on `worker-1`, wrk2 on load-gen node
- **Same social graph** — socfb-Reed98 (963 users, ~18,800 edges) initialized fresh per repetition
- **Jaeger distributed tracing** — 100% sampling (DSB native tracing, no Istio mTLS complications)
- **5 repetitions with fresh DB init** — controls MongoDB WAL and Redis eviction variance
- **Separate namespace `dsb-exp11`** — avoids any accidental Istio ambient mesh coverage

---

## What Is Deliberately Absent (vs Experiment 12)

| Component | Experiment 12 | Experiment 11 |
|-----------|--------------|--------------|
| Istio Ambient Mode | ✅ enabled | ❌ not installed |
| ztunnel DaemonSet | ✅ on all nodes | ❌ absent |
| mTLS between pods | ✅ enforced by ztunnel | ❌ plain HTTP |
| Namespace label `istio.io/dataplane-mode=ambient` | ✅ set | ❌ **must NOT be set** |

> [!WARNING]
> **CRITICAL: You CANNOT run Experiment 11 while Istio is installed on the cluster.**
> Even if `dsb-exp11` is not enrolled in the mesh, the `istio-cni-node` DaemonSet will still intercept pod networking, causing unauthorized sandbox errors or adding asymmetric CNI overhead that ruins the baseline.
> 
> Before deploying Experiment 11, you **must completely purge Istio** from the nodes:
> ```bash
> bash scripts/cleanup/uninstall-istio-completely.sh
> ```
| ztunnel CPU metrics | ✅ collected | ❌ N/A — replaced by plain pod CPU |

---

## Cluster Configuration

| Node | Actual Name | Role |
|------|-------------|------|
| worker-0 | `default-pool-ssp-11b2c93c3e14` | Victim-tier DSB services |
| worker-1 | `default-pool-ssp-157a7771fb89` | Mid-tier services (nginx, DB, Jaeger) |
| load-gen | `default-pool-ssp-865907b54154` | wrk2 load generators |

Each node: **4 vCPUs, 8 GB RAM**, Kubernetes v1.35.2

> **No Istio installed.** If Istio happens to be running on this cluster (from Exp 12/13), ensure the `dsb-exp11` namespace does NOT have the `istio.io/dataplane-mode=ambient` label. The deploy scripts enforce this automatically.

---

## Repository Structure

- `configs/` → Kubernetes manifests, plain-K8s Helm values, wrk2 scripts, observability
- `scripts/deploy/` → Deploy DSB (no Istio), Jaeger, social graph init, verification
- `scripts/run/` → Run experiment, saturation sweep, sequential runner
- `scripts/metrics/` → Jaeger trace collection, kubectl top snapshots
- `scripts/cleanup/` → Teardown and idempotent cleanup-deploy cycle
- `scripts/utils/` → Pre-flight checks (no Istio requirement), node labeling, venv setup
- `workloads/` → Load profiles, request bodies, wrk2 schedules
- `data/` → Raw wrk2 JSON, processed CSVs, run metadata
- `results/` → Figures, tables, final report
- `src/` → Python parsers (same as Exp 12), analysis, plotting
- `docs/` → Detailed methodology, architecture, design, threats-to-validity
- `notebooks/` → Jupyter analysis notebooks
- `ci/` → Smoke test, lint check, full reproducibility runner

---

## Step-by-Step Execution

All steps are run from the **Experiment11 root directory**:
```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment11
```

---

### Step 0 — Create & Activate Python Virtual Environment

> **This runs first.** The venv isolates all Python dependencies (`pandas`, `scipy`, `matplotlib`, `numpy`) inside the project directory.

```bash
cd Experiment11
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

Or using Make:
```bash
make setup
make check-venv
```

---

### Step 1 — Check Prerequisites

```bash
bash scripts/utils/check-prereqs.sh
```

Run this **inside the active venv** (from Step 0). It validates everything:

| Category | What it does |
|----------|-------------|
| **Python venv** | Confirms `(.venv)` is active. If not, shows a box telling you to run Step 0 first. |
| **Python packages** | Verifies `pandas`, `matplotlib`, `scipy`, `numpy` are importable with versions. |
| **System tools** | Checks `kubectl`, `helm`, `jq`, `curl`, `git`. Auto-installs missing ones via `apt`. |
| **wrk2** | Checks common paths. If missing, prints compile-from-source instructions. |
| **Cluster state** | Verifies `kubectl` connectivity, 3 nodes Ready. |
| **Istio (informational)** | Checks if ztunnel DaemonSet exists — informs but does NOT fail if it does. Experiment 11 relies on namespace isolation, not Istio absence from the cluster. |
| **DSB repo** | Clones DeathStarBench to `/opt/dsb` if not present. |

To **check only** without auto-installing:
```bash
bash scripts/utils/check-prereqs.sh --check-only
```

Or:
```bash
make check
```

---

### Step 2 — Label Nodes

```bash
bash scripts/utils/label-nodes.sh
```

Assigns `role=worker-0`, `role=worker-1`, `role=load-gen` labels for deterministic pod scheduling.
(Identical to Experiment 12 labeling — same physical cluster.)

Or:
```bash
make label
```

---

### Step 3 — Deploy Everything (One-Shot, Plain K8s)

```bash
bash scripts/deploy/deploy-setup.sh
```

This single script:
- Creates `dsb-exp11` namespace **without** `istio.io/dataplane-mode` label (plain K8s)
- Deploys DSB Social-Network via Helm with **`sidecar.istio.io/inject: "false"`** annotation — ensures no sidecar injection even if Istio is present on the cluster
- Deploys Jaeger (all-in-one) on `worker-1` for distributed tracing
- Waits for all pods to be `Running + Ready`
- Initializes the socfb-Reed98 social graph in MongoDB
- Verifies pod placement

Or:
```bash
make deploy
```

> **Key difference from Experiment 12:** No `istio.io/dataplane-mode: ambient` namespace annotation. No `istio/telemetry.yaml` applied. No `peer-authentication.yaml`. Traffic flows pod-to-pod without any proxy in the data path.

---

### Step 3.5 — Initialize Social Graph ⚠️ MANDATORY

> **This step is required before every experiment run.** Without it, every request hangs for 40+ seconds (social-graph MongoDB has 0 edges), producing completely invalid latency data (P50 ~45s, ~20 RPS actual vs 50 target, thousands of timeouts).

```bash
bash scripts/deploy/init-graph.sh
```

What it does:
- Port-forwards `nginx-thrift` to `localhost:18080`
- Runs DSB's `init_social_graph.py` with `socfb-Reed98` (963 users, ~18,800 edges)
- Verifies MongoDB edge count (`db.social_graph.count()` must be > 0)
- Smoke-tests the user-timeline endpoint

**Expected output:**
```
✔ Social graph initialized (socfb-Reed98: 963 users, ~18,800 edges)
  social_graph collection count: 18836
✔ MongoDB verified: 18836 edges in social_graph
✔ Smoke test passed — user timeline readable
═══════════════════════════════════════════════════
  Social graph init COMPLETE ✅
  Namespace: dsb-exp11 (plain Kubernetes, NO Istio)
  Graph:     socfb-Reed98 (963 users)
  MongoDB:   18836 edges
═══════════════════════════════════════════════════
  Next: run the experiment
    sudo bash scripts/run/run-experiment.sh
```

> **Signs of failure:** If MongoDB count is 0, do NOT proceed. Check pod logs:
> ```bash
> kubectl logs -n dsb-exp11 -l service=social-graph-service --tail=30
> ```

---

### Step 4 — Verify Deployment

```bash
bash scripts/deploy/verify-deployment.sh
```

Checks:
- All DSB pods are `Running`
- Victim-tier pods (social-graph, user-service, media-service) are on `worker-0`
- Mid-tier pods (nginx, MongoDB, Redis, Jaeger) are on `worker-1`
- Namespace `dsb-exp11` has **NO** `istio.io/dataplane-mode` label
- NGINX ClusterIP is accessible
- Jaeger UI is reachable

Or:
```bash
make verify
```

---

### Step 5 — Run Saturation Sweep (One-Time)

```bash
bash scripts/run/run-saturation-sweep.sh
```

> If the above doesn't work (port not accessible), open a second terminal and run:
> ```bash
> kubectl port-forward svc/nginx-thrift 18080:8080 -n dsb-exp11
> ```
> then run the sweep in the first terminal.

Sweeps compose-post from 50 → 600 RPS to find the P99 knee on **plain K8s**. Compare the knee point here vs Experiment 12 to see the Istio overhead. **Run once** before the 5-repetition baseline.

Or:
```bash
make sweep
```

---

### Step 6 — Run Baseline Repetitions

> **⚠️ CRITICAL METHODOLOGY UPDATE:** To match the realistic steady-state conditions of Experiment 13, **we NO LONGER tear down or re-initialize between runs**. The cluster stays warm.

**Recommended — sequential script:**
```bash
chmod +x scripts/run/run_sequential_experiments.sh
sudo bash scripts/run/run_sequential_experiments.sh 5
```

The script automatically executes the warm-cluster methodology:
1. `warmup.sh` (ONCE at start) → 60s at 800 RPS (200+300+300) to fill Redis/memcached and warm JIT.
2. `run-experiment.sh` → 180s measurement (3 endpoints in parallel).
3. Cooldown → 90s sleep.
4. (Repeats steps 2 and 3 for N reps — no teardowns, no graph resets).

Results saved to `data/raw/run_001/` through `run_005/`.

**Or run manually (order is critical):**
```bash
# ① If this is the FIRST run, initialize the graph and warm caches
bash scripts/deploy/init-graph.sh
bash scripts/run/warmup.sh "127.0.0.1" "60s"

# ② Run the experiment (measure only)
sudo bash scripts/run/run-experiment.sh

# ③ Wait 90s before next manual run (do NOT re-init graph)
sleep 90
```

**Sanity check — healthy run_001 output:**
```
compose-post:   Requests/sec: ~50    P50 ~200–400ms   timeout 0
home-timeline:  Requests/sec: ~100   P50 ~150–300ms   timeout 0
user-timeline:  Requests/sec: ~100   P50 ~150–300ms   timeout 0
```
If you see `Requests/sec ~20` or `timeout 5000+` → graph was not initialized. Delete the bad run (`rm -rf data/raw/run_NNN/`) and redo from ①.

Or via Make:
```bash
make run-seq N=5
```


**Output per run** (`data/raw/run_NNN/`):
```
compose-post.txt      ← wrk2 HdrHistogram + summary
home-timeline.txt
user-timeline.txt
pod-cpu.txt           ← kubectl top snapshot (pods in dsb-exp11)
node-cpu.txt          ← kubectl top nodes
pod-placement.txt     ← pod placement verification
jaeger-traces.json    ← Jaeger spans (if Jaeger running)
run-metadata.txt      ← run ID, timestamps, "mesh: NONE"
```

> **Difference from Experiment 12:** No `ztunnel-top.txt` — there is no ztunnel to monitor. The `run-metadata.txt` records `Service mesh: NONE (plain Kubernetes)`.

---

### Step 7 — Analyze Results

```bash
source .venv/bin/activate

# Parse all raw wrk2 outputs into CSVs
python3 src/parser/wrk2_parser.py \
  --runs-dir data/raw/ \
  --output   data/processed/csv/

# Compute statistics (median, 95% CI, CV)
python3 src/analysis/stats.py \
  --input  data/processed/csv/ \
  --output results/tables/summary.csv
```

Or:
```bash
make analyze
```

This produces:
- `results/tables/summary.csv` — median + 95% CI per endpoint per percentile (P50/P75/P90/P95/P99/P99.9/P99.99)
- `results/tables/variance.csv` — CV per metric (flags CV > 5%)

> This `summary.csv` is the plain-K8s counterpart to `Experiment12/results/tables/summary.csv`. Comparing the two directly shows the Istio Ambient overhead.

---

### Step 8 — Generate Paper Figures

The experiment produces **4 figure types**. Run them all after `stats.py`:

```bash
source .venv/bin/activate

# ── A. Latency Percentiles per Endpoint (bar chart: P50 / P99 / P99.99) ───────
python3 src/plotting/latency_plots.py \
  --mode latency \
  --data data/processed/csv/ \
  --output results/figures/latency-cdf/
# → results/figures/latency-cdf/baseline-percentile-bars.{pdf,png}

# ── B. Throughput vs Offered Load (dual-panel: achieved RPS + P99 latency) ────
python3 src/plotting/throughput_plots.py \
  --data data/raw/saturation-sweep/ \
  --output results/figures/throughput/
# → results/figures/throughput/throughput-vs-load.{pdf,png}

# ── C. Saturation Sweep (P99 latency vs offered load, for context) ───────────
python3 src/plotting/saturation_plots.py \
  --data data/raw/saturation-sweep/ \
  --output results/figures/throughput/
# → results/figures/throughput/saturation-sweep.{pdf,png}

# ── D. Endpoint Tail Latency CCDF (complementary CDF with log Y-axis) ──────────
python3 src/plotting/cdf_plots.py \
  --runs-dir data/raw/ \
  --output results/figures/latency-cdf/
# → results/figures/latency-cdf/tail-cdf.{pdf,png}
# → results/figures/latency-cdf/latency-cdf.{pdf,png}

# ── E. Jaeger per-hop flame chart (if Jaeger sampling enabled) ────────────────
python3 src/plotting/latency_plots.py \
  --mode jaeger \
  --data data/raw/run_001/jaeger-traces.json \
  --output results/figures/traces/
```

Or all at once:
```bash
make figures
```

**Output directory layout after all figures are generated:**
```
results/figures/
├── latency-cdf/
│   ├── baseline-percentile-bars.{pdf,png}   # Plot A  (P50/P99/P99.99 bars)
│   ├── tail-cdf.{pdf,png}                   # Plot D  (CCDF, log scale)
│   └── latency-cdf.{pdf,png}               # Plot D  (linear + log panel)
├── throughput/
│   ├── throughput-vs-load.{pdf,png}         # Plot B  (achieved RPS + P99)
│   └── saturation-sweep.{pdf,png}           # Plot C  (saturation context)
└── traces/
    └── jaeger-flamechart-compose.pdf        # Jaeger (when available)
```

---

### Step 9 — View Results

```bash
# Summary table (baseline latency, plain K8s)
cat results/tables/summary.csv

# Variance report
cat results/tables/variance.csv
```

---

## Full Workflow via Make (recommended)

```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment11

make setup          # Step 0: create .venv + install deps
make check          # Step 1: pre-flight checks (no Istio required)
make deploy         # Step 3: deploy plain K8s DSB + Jaeger

bash scripts/deploy/init-graph.sh   # Step 3.5: ⚠️ MANDATORY — init social graph (run after deploy)
# → check output: "MongoDB: NNNNN edges" must be > 0 before proceeding

make verify         # Step 4: verify deployment (checks NO Istio label)
make sweep          # Step 5: saturation sweep

bash scripts/deploy/init-graph.sh   # ⚠️ Re-init before run set (always!)

make run-seq N=5    # Step 6: 5 sequential baseline repetitions
make analyze        # Step 7: parse + stats
make figures        # Step 8: all 4 paper figures
```

---

## Metrics Reference

### A. End-to-End User Metrics (wrk2, auto-collected per run)

| Metric | Source file | How parsed |
|--------|-------------|-----------|
| P50, P99, P99.9, P99.99 (ms) | `compose-post.txt` | `wrk2_parser.py` HdrHistogram |
| Achieved throughput (RPS) | `compose-post.txt` | `Requests/sec:` line |

Endpoints: **compose-post** (50 RPS), **home-timeline** (100 RPS), **user-timeline** (100 RPS).

### B. Internal Service Metrics (Jaeger, 100% sampling)

Services traced on compose-post call chain:
`nginx-thrift` → `compose-post-service` → `social-graph-service`, `user-service`, `media-service`, `text-service`, `url-shorten-service`, `unique-id-service`, `post-storage-service`

### C. Infrastructure Metrics (snapshots at end of each run)

| File | Meaning |
|------|---------|
| `pod-cpu.txt` | `kubectl top pod -n dsb-exp11` snapshot |
| `node-cpu.txt` | `kubectl top node` snapshot |
| `pod-placement.txt` | Pod-to-node placement verification |

> **Comparison with Experiment 12:** Experiment 12 also has `ztunnel-top.txt` (ztunnel CPU/memory/threads time-series). Experiment 11 has no such file — the ztunnel simply doesn't exist. The **absence of this file is by design** and documents that the data path has no proxy overhead.

---

## Expected Results

> Updated targets based on expected plain K8s performance at 50/100/100 RPS.

| Endpoint | Target RPS | Expected P50 (ms) | Expected P99 (ms) | Expected P99.99 (ms) | Error Rate |
|----------|-----------|------------------|------------------|---------------------|------------|
| compose-post | 50 | **< 200** | **< 1,500** | **< 2,000** | < 1% |
| home-timeline | 100 | **< 120** | **< 1,400** | **< 1,800** | < 0.5% |
| user-timeline | 100 | **< 100** | **< 1,300** | **< 1,700** | < 0.5% |

> These estimates are **lower than Experiment 12** because there is no ztunnel proxy overhead. The actual improvement depends on CPU scheduling and network stack — typically 10–30% lower tail latency on plain K8s vs Istio Ambient.

**Key acceptance criteria:**
- ✅ Achieved RPS matches target (system not saturated)
- ✅ Zero HTTP 4xx/5xx errors (application correctness confirmed)
- ✅ `run-metadata.txt` records `Service mesh: NONE (plain Kubernetes)` in all runs
- ✅ Namespace `dsb-exp11` has NO `istio.io/dataplane-mode` label
- ✅ P99.99 is measurably lower than Experiment 12's P99.99 at the same load point

---

## Makefile Targets

```bash
make check           # Pre-flight checks (no Istio required)
make deploy          # Full deploy (labels + DSB + Jaeger + graph init)
make verify          # Verify deployment state (no ztunnel checks)
make sweep           # Saturation sweep (one-time, before baseline)
make run             # Single experiment repetition
make run-seq N=5     # 5 sequential repetitions
make analyze         # Parse + compute statistics
make figures         # All 4 paper figures
make clean           # Full teardown (namespace dsb-exp11)
make reset           # Cleanup + redeploy (idempotent)
```

---

## Cleanup

### Pure Cleanup (Teardown Only)
```bash
bash scripts/cleanup/cleanup.sh
```

### Cleanup and Redeploy (Idempotent — Used Between Repetitions)
```bash
bash scripts/cleanup/cleanup-deploy-setup.sh
```

---

## Directory Layout

```
Experiment11/
├── .venv/                            ← Python virtual environment (created by make setup)
├── Makefile                          ← All targets: setup, deploy, run, analyze, figures
├── requirements.txt                  ← Python deps (matplotlib, numpy, pandas, scipy)
├── configs/
│   ├── wrk2/
│   │   ├── rates.env                 ← DSB rates (50/100/100 RPS — same as Exp12)
│   │   ├── saturation-sweep.env      ← Sweep parameters
│   │   ├── compose-post.lua
│   │   ├── read-home-timeline.lua
│   │   └── read-user-timeline.lua
│   ├── kubernetes/
│   │   └── namespace.yaml            ← dsb-exp11 namespace (NO Istio label)
│   └── deathstarbench/social-network/
│       ├── base/
│       │   └── helm-values-plain.yaml ← no-mesh + 512Mi memory limits (fixes OOMKill)
│       └── placement/
│           ├── worker0-affinity.yaml  ← victim-tier → worker-0
│           └── worker1-affinity.yaml  ← mid-tier → worker-1
├── data/
│   ├── raw/run_NNN/
│   │   ├── compose-post.txt          ← wrk2 HdrHistogram output
│   │   ├── home-timeline.txt
│   │   ├── user-timeline.txt
│   │   ├── pod-cpu.txt               ← kubectl top pod snapshot
│   │   ├── node-cpu.txt              ← kubectl top node snapshot
│   │   ├── pod-placement.txt         ← pod-to-node mapping
│   │   ├── jaeger-traces.json        ← Jaeger spans (if available)
│   │   └── run-metadata.txt          ← "Service mesh: NONE (plain Kubernetes)"
│   └── processed/csv/                ← Parsed CSVs
├── results/
│   ├── tables/summary.csv            ← Baseline latency (plain K8s)
│   └── figures/                      ← 4 output figures
├── scripts/
│   ├── run/
│   │   ├── run-experiment.sh         ← Single run (no ztunnel logic)
│   │   ├── run-saturation-sweep.sh   ← Saturation sweep
│   │   └── run_sequential_experiments.sh ← N-repetition driver
│   ├── deploy/
│   │   ├── deploy-setup.sh           ← Plain K8s deploy (no Istio steps)
│   │   ├── verify-deployment.sh      ← Checks NO Istio label
│   │   ├── deploy-observability.sh   ← Jaeger on worker-1
│   │   └── init-graph.sh             ← Social graph init
│   ├── cleanup/
│   │   ├── cleanup.sh                ← Teardown dsb-exp11
│   │   └── cleanup-deploy-setup.sh   ← Idempotent reset
│   └── utils/
│       ├── setup-venv.sh             ← Creates .venv
│       ├── label-nodes.sh            ← Node labeling
│       └── check-prereqs.sh          ← Pre-flight checks (no Istio hard req)
└── src/
    ├── parser/
    │   └── wrk2_parser.py            ← Same parser as Exp12 (identical output format)
    ├── analysis/
    │   └── stats.py                  ← Same stats pipeline as Exp12
    └── plotting/
        ├── latency_plots.py          ← P50/P99/P99.99 bars
        ├── throughput_plots.py       ← Throughput vs load
        ├── saturation_plots.py       ← Saturation sweep
        └── cdf_plots.py              ← CCDF log-scale
```

---

## Debugging Notes & Known Issues

This section documents bugs found and fixed during initial test runs. **Read this before troubleshooting bad data.**

### Bug 1 — OOMKill on `user-mongodb` (128Mi → 512Mi)

**Symptom:** ~20 RPS achieved (vs 50/100/100 target), hundreds of timeouts, P50 ~45–80s.

**Diagnosis:**
```bash
kubectl describe pod -n dsb-exp11 -l service=user-mongodb | grep -A5 "Last State"
# Shows: Reason: OOMKilled, Exit Code: 137
```

**Root cause:** `helm-values-plain.yaml` had no resource limits → DSB chart default = **128Mi** per pod → `user-mongodb` is killed mid-run when memory spikes under 50 RPS load → all in-flight requests timeout.

**Fix:** Added global resource limits to `configs/deathstarbench/social-network/base/helm-values-plain.yaml` matching Exp12:
```yaml
global:
  resources:
    limits:
      cpu: "500m"
      memory: "512Mi"   # was 128Mi (DSB default) → OOMKilled under load
```
Then re-deploy: `bash scripts/deploy/deploy-setup.sh`

---

### Bug 2 — Social Graph `db.social_graph.count() = 0` (false alarm)

**Symptom:** After running `init-graph.sh`, verification showed `0` in MongoDB.

**Root cause:** DSB's `social-graph-service` stores follow relationships **in Redis, not MongoDB**. The mongo count query was always wrong.

**Correct verification:**
```bash
# ✅ Correct: check Redis
kubectl exec -n dsb-exp11 deploy/social-graph-redis -- redis-cli DBSIZE
# Expected: ~1924 keys = 962 users × 2 (followees + followers list per user)

# ✅ Correct: smoke test via nginx
kubectl port-forward svc/nginx-thrift 18080:8080 -n dsb-exp11 &
curl -s "http://127.0.0.1:18080/wrk2-api/user-timeline/read?user_id=1&start=0&stop=3"
# Expected: JSON with post data — if empty array, graph not loaded

# ❌ Wrong (always 0 even when graph is loaded):
kubectl exec -n dsb-exp11 deploy/social-graph-mongodb -- \
  mongo --quiet --eval "db.social_graph.count()" social_graph
```

---

### Bug 3 — `kubectl` hanging when run as root / via `sudo`

**Symptom:** `kubectl` commands time out when run inside `sudo bash scripts/...` because root has no kubeconfig at `/root/.kube/config`.

**Fix:** Both `init-graph.sh` and `run-experiment.sh` now auto-detect and use appu's kubeconfig:
```bash
if [[ ! -f "${KUBECONFIG:-$HOME/.kube/config}" ]] && [[ -f /home/appu/.kube/config ]]; then
  export KUBECONFIG=/home/appu/.kube/config
fi
```

**Or run kubectl directly as appu:**
```bash
sudo -u appu kubectl get pods -n dsb-exp11
```

---

### Bug 4 — Missing `-T 10s` timeout in wrk2 calls

**Symptom:** 5,000+ socket timeouts per run even at idle load. P50 = 45s.

**Root cause:** `run-experiment.sh` was missing `-T 10s` flag → default 2s socket timeout triggers because `kubectl port-forward` adds ~3–5s latency on the first packet.

**Fix:** All `wrk2` invocations in `scripts/run/run-experiment.sh` now include `-T 10s`.

---

### Healthy Run Checklist

After a good run, verify:
```bash
# 1. RPS should match targets
grep "Requests/sec" data/raw/run_001/compose-post.txt      # expect ~49-50
grep "Requests/sec" data/raw/run_001/home-timeline.txt     # expect ~99-100
grep "Requests/sec" data/raw/run_001/user-timeline.txt     # expect ~99-100

# 2. Zero timeouts
grep "timeout" data/raw/run_001/compose-post.txt           # expect timeout 0

# 3. MongoDB never restarted
kubectl get pods -n dsb-exp11 | grep mongodb               # RESTARTS should all be 0

# 4. Reasonable P50 (300–800ms is normal for plain K8s at this load)
grep "50.000%" data/raw/run_001/compose-post.txt
```

**Observed first clean run (run_001, 20260429_170904):**
| Endpoint | RPS | Mean | Max | Timeouts |
|----------|-----|------|-----|----------|
| compose-post | 49.73 | 521ms | 2.3s | 0 |
| home-timeline | 99.76 | 629ms | 3.7s | 0 |
| user-timeline | 99.67 | 535ms | 4.3s | 0 |

---

## Cleanup

```bash
# Full teardown
make clean
```

---

*Experiment 11 — Plain Kubernetes Baseline (No Service Mesh) · SSP T2 2025*
