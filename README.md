# SSP Service Mesh: Shared ztunnel Interference in Istio Ambient Mode

An empirical study of tail-latency degradation caused by shared node-level proxy contention in Istio Ambient Mode. This repository contains fully reproducible experiments, eBPF instrumentation, and analysis pipelines that trace interference from a synthetic observation through a root-cause proof and into a real-world microservice benchmark.

---

## Overview

Istio Ambient Mode replaces per-pod sidecar proxies with a single **ztunnel** process per node — a shared dataplane that intercepts all mesh traffic for every pod on that node. This architectural shift improves resource efficiency but creates a new failure mode: **noisy-neighbor interference via shared proxy contention**.

When a high-throughput workload co-located on the same node as a latency-sensitive service competes for the shared ztunnel, tail latency degrades even when CPU and network are not saturated. The degradation is invisible to traditional monitoring (median latency stays stable) and cannot be attributed to application code.

This project answers three questions:

1. **Does** shared-ztunnel interference cause measurable tail-latency amplification? *(Section 1)*
2. **Why** does it happen — what is the exact causal mechanism? *(Section 2)*
3. **Does it matter** in real microservice workloads? *(Section 4)*

---

## Research Narrative Arc

| Section | Experiment | Role | Core Finding |
|---------|-----------|------|-------------|
| 1 | Exp 3 | Observation | Shared ztunnel causes tail-latency amplification in synthetic workloads; P99 grows with co-tenant load while P50 stays stable |
| 2 | Exp 4 | Root-cause proof | eBPF instrumentation isolates queue delay (t4 − t3 in the 5-timestamp pipeline) as the single growing latency component; CPU-latency decoupling confirms it is not a resource-saturation effect |
| 4 | Exp 11 | Control group | DeathStarBench Social Network on plain Kubernetes (no mesh) establishes the mesh-free performance baseline |
| 4 | Exp 12 | Mesh baseline | Same DSB workload under Istio Ambient establishes the "mesh tax" (ztunnel overhead relative to Exp 11) |
| 4 | Exp 13 | Main result | Noisy-neighbor injection into the DSB cluster reproduces real-world interference; P99 and P99.9 amplify significantly across three victim-service pinning cases |

**Cross-experiment comparisons**

- **Exp 11 vs 12**: Mesh tax — ztunnel overhead on a clean cluster
- **Exp 12 vs 13**: Noisy-neighbor tax — interference cost on top of the baseline mesh
- **Exp 11 vs 12 vs 13**: Full waterfall breakdown of cumulative overhead

---

## Repository Structure

```
SSP-Service-Mesh/
├── install istio.md                                  # istioctl v1.23.0 setup guide
│
├── Section_1_Core_Interference_Categorization/
│   └── Experiment3/                                  # Shared-ztunnel tail-latency observation
│
├── Section_2_Root_Cause_Proof/
│   └── Experiment4/                                  # eBPF 5-timestamp latency decomposition
│
├── Section_3_Negative_Results/                       # Placeholder (future EuroSys work)
│
└── Section_4_Real_Workload_Validation/
    ├── Experiment11/                                  # DSB baseline — no mesh
    ├── Experiment12/                                  # DSB baseline — Istio Ambient
    └── Experiment13/                                  # DSB + noisy-neighbor injection
```

Each experiment directory follows a consistent layout:

```
ExperimentN/
├── README.md               # Step-by-step execution guide
├── WHAT_IT_IS.md           # One-line summary and research context
├── implementation.md       # (optional) Design rationale and key decisions
├── Makefile                # Build and analysis targets
├── requirements.txt        # Python dependencies
├── Dockerfile              # Reproducible analysis container
├── cluster-setup/          # Namespace YAML, node-labeling scripts, verification
├── workloads/              # Kubernetes deployment and service manifests
├── ebpf/                   # (Exp 4 only) bpftrace scripts
├── traffic/                # Load-generation scripts
├── scripts/
│   ├── deploy/             # setup, init-graph, verify-deployment
│   ├── run/                # run-experiment, run-sequential, saturation-sweep, warmup
│   ├── metrics/            # capture-ztunnel-stats, kubectl-top snapshots
│   └── cleanup/            # idempotent teardown
├── analysis/               # Python analysis and plotting modules
├── docs/                   # Methodology, threat analysis, architecture diagrams
└── results/
    ├── raw/                # Timestamped experiment outputs (wrk2 JSON, ztunnel metrics)
    ├── processed/          # Parsed CSVs per run
    ├── plots_lvl1-4/       # Generated figures
    └── tables/             # Summary statistics
```

---

## Prerequisites

### Cluster Requirements

- Kubernetes cluster with **3 worker nodes** (4 vCPU, 8 GB RAM each)
  - `worker-0` — victim/DSB services (Exp 11–13)
  - `worker-1` — mid-tier services, databases, Jaeger
  - Load-gen node — wrk2 clients
- Kernel **≥ 6.8.0** (required for Exp 4 eBPF probes)
- bpftrace **≥ 0.14.0** (Exp 4 only)

### Istio Ambient Mode

Install `istioctl` v1.23.0:

```bash
cd /tmp
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.0 sh -
sudo mv /tmp/istio-1.23.0/bin/istioctl /usr/local/bin/
istioctl version
```

Install Istio with Ambient profile on your cluster:

```bash
istioctl install --set profile=ambient --skip-confirmation
```

> Exp 11 (no-mesh control) must be run on a cluster **without** Istio installed, or in a namespace with all injection disabled.

### Python Dependencies

Each experiment ships its own `requirements.txt`. The set is consistent across all experiments:

```
pandas>=1.5.0
matplotlib>=3.6.0
scipy>=1.10.0
numpy>=1.24.0
aiohttp>=3.8.0
```

Install into a virtual environment before running any analysis:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Load Generation

- **Fortio** (Exp 3) — installed as a Kubernetes pod via the provided manifests
- **wrk2** (Exp 11–13) — open-loop load generator; must be available on the load-gen node. The `-D exp` flag is required to avoid coordinated omission bias.

---

## Experiment 3 — Shared-ztunnel Tail-Latency Amplification

**Section 1 | Core Interference Categorization**

### What It Is

Three pods (`svc-a`, `svc-b`, `client`) are pinned to a single Kubernetes node via `nodeSelector` so all traffic flows through one shared ztunnel instance. `svc-b` is ramped from 0 to 1000+ RPS while `svc-a` runs at constant load. The experiment measures whether `svc-b`'s growing throughput degrades `svc-a`'s tail latency even though `svc-a`'s workload never changes.

**Core hypothesis:** Shared ztunnel creates proxy queue contention → tail latency amplification even when median latency is stable.

### Setup

```bash
cd Section_1_Core_Interference_Categorization/Experiment3
make setup          # label node, deploy pods, verify readiness
```

### Running

```bash
make run            # generates a timestamped RUN_ID
```

The run script sweeps `svc-b` load across several QPS levels, collecting Fortio latency histograms and ztunnel CPU samples (via Prometheus) at each level.

### Analysis

Analysis is organized into four levels of increasing detail. Each level produces figures in `results/plots_lvlN/`.

```bash
make build                            # build Docker analysis image
make run-lvl1 RUN_ID=<timestamp>      # raw latency distributions (P50, P90, P99, P99.9)
make run-lvl2 RUN_ID=<timestamp>      # P99 amplification curve vs svc-b load
make run-lvl3 RUN_ID=<timestamp>      # ztunnel CPU vs tail-latency correlation
make run-lvl4 RUN_ID=<timestamp>      # summary: baseline vs peak interference
```

### Key Outputs

| Figure | Description |
|--------|-------------|
| `percentiles_multi.png` | P50/P99/P99.9 across all load levels |
| `tail_ratio_multi.png` | Tail amplification ratio (P99 / P50) as `svc-b` load grows |
| `queue_vs_amp_multi.png` | ztunnel CPU utilization vs P99 amplification |
| `amplification_multi.png` | Absolute P99 increase from baseline |

---

## Experiment 4 — Root-Cause Proof via eBPF Latency Decomposition

**Section 2 | Root Cause Proof**

### What It Is

This experiment instruments the ztunnel dataplane with bpftrace probes to decompose end-to-end request latency into five pipeline segments, isolating exactly which segment grows under load. It directly tests the hypothesis that **proxy queue delay** (not network jitter, kernel scheduling, or CPU saturation) is the root cause of the interference observed in Exp 3.

### The 5-Timestamp Pipeline

```
t1  Packet arrives at kernel TCP receive buffer         (kprobe: tcp_rcv_established)
t2  Bytes delivered to ztunnel userspace               (kprobe: recv / read)
t3  Request enqueued into proxy work queue              (uprobe: ztunnel enqueue)
t4  Request dequeued, worker thread begins execution    (uprobe: ztunnel dequeue)
t5  Response written back to socket                    (kprobe: tcp_sendmsg)
```

**Queue delay = t4 − t3.** This is the single metric that grows with `svc-b` load.

The experiment also records **worker thread occupancy** via scheduler tracepoints (`sched_switch`) to correlate queue delay with the fraction of time worker threads are occupied.

### Setup

```bash
# Install bpftrace (kernel >= 6.8.0 required)
cd Section_2_Root_Cause_Proof/Experiment4/ebpf
./install-bpftrace.sh

# Deploy the same single-node pod layout as Exp 3
cd ..
make setup
```

### Running

```bash
# Run at each load level: 0, 100, 500, 1000 RPS
make run LOAD_LEVEL=0
make run LOAD_LEVEL=100
make run LOAD_LEVEL=500
make run LOAD_LEVEL=1000
```

Each run simultaneously:
1. Generates load via Fortio
2. Runs `latency_decomp.bt` to capture the 5-timestamp pipeline
3. Runs `sched_occupancy.bt` to record worker thread occupancy
4. Saves raw bpftrace output and Fortio JSON to `results/raw/<load_level>/`

### Analysis

```bash
make run-lvl1     # Stacked latency breakdown per pipeline segment + histograms
make run-lvl2     # Queue delay vs load curve + worker occupancy scatter/regression
make run-lvl3     # HoL-blocking timeline reconstruction + CPU-latency decoupling proof
make run-lvl4     # Cross-level summary
```

### Key Outputs

| Figure | Description |
|--------|-------------|
| `stacked_latency.png` | Stacked bar of each pipeline segment across load levels |
| `queue_delay_vs_load.png` | Queue delay (t4−t3) as the sole growing component |
| `worker_occupancy_scatter.png` | Scatter + regression: occupancy → queue delay |
| `hol_blocking_timeline.png` | Head-of-line blocking events reconstructed from timestamps |
| `cpu_latency_decoupling.png` | ztunnel CPU flat while queue delay grows (not a saturation effect) |

---

## Experiment 11 — DeathStarBench Baseline (No Mesh)

**Section 4 | Real Workload Validation — Control Group**

### What It Is

Runs the [DeathStarBench](https://github.com/delimitrou/DeathStarBench) Social Network microservice benchmark on plain Kubernetes with **no service mesh**. This is the control group that isolates application-layer latency from any Istio overhead. Results from this experiment anchor the "mesh tax" comparison with Exp 12.

- **Namespace:** `dsb-exp11` — no `istio.io/dataplane-mode` label; all pods annotated `sidecar.istio.io/inject: "false"`
- **Social graph:** `socfb-Reed98` (963 users, ~18,800 edges) loaded into MongoDB and Redis
- **Node assignment:** DSB victim services on `worker-0`; databases, Jaeger, mid-tier on `worker-1`

### Load Profile

| Endpoint | RPS | Notes |
|----------|-----|-------|
| `/wrk2-api/user/compose-post` | 50 | Write-path, most sensitive |
| `/wrk2-api/user/read-home-timeline` | 100 | Read-path, fan-out |
| `/wrk2-api/user/read-user-timeline` | 100 | Read-path, per-user |

### Running

```bash
cd Section_4_Real_Workload_Validation/Experiment11

# One-time cluster preparation
make setup          # label nodes, deploy DSB, initialize social graph

# Measurement (5 sequential repetitions, warm-cluster methodology)
make run-seq N=5

# Parse and analyze
make analyze
make figures
```

**Warm-cluster methodology:** The social graph is initialized once. All five repetitions run back-to-back without teardown or re-initialization, capturing realistic steady-state (cache-warm, JIT-compiled) behavior.

### Expected Results

| Metric | Expected Range |
|--------|---------------|
| compose-post P50 | < 200 ms |
| compose-post P99 | < 1500 ms |
| compose-post P99.99 | < 2000 ms |
| Achieved RPS | Matches target ± 2% |
| HTTP errors | 0 |

### Cleanup

```bash
make clean          # deletes namespace and all deployed resources
```

---

## Experiment 12 — DeathStarBench Baseline (Istio Ambient)

**Section 4 | Real Workload Validation — Mesh Baseline**

### What It Is

Identical workload to Exp 11, but with Istio Ambient Mode enabled. The namespace `dsb-exp` carries the `istio.io/dataplane-mode: ambient` label, routing all pod traffic through the ztunnel DaemonSet. This experiment establishes a reproducible ambient-mode performance baseline and quantifies the mesh tax relative to Exp 11.

Additional data collected vs Exp 11:
- ztunnel CPU and memory every 5 seconds (`data/raw/run_NNN/ztunnel-top.txt`)
- ztunnel worker thread counts and queue depth

### Setup

```bash
cd Section_4_Real_Workload_Validation/Experiment12

# Verify Istio Ambient is installed on the cluster
istioctl verify-install

# Saturation sweep (run once before baseline measurements)
make saturation-sweep    # finds the load knee; results saved to docs/

make setup               # label nodes, deploy with ambient annotation, init social graph
make warmup              # warm caches and JIT before measurement phase
```

### Running

```bash
make run-seq N=5         # 5 warm repetitions
make analyze
make figures
```

### Expected Results

P99 and P99.9 latencies will be measurably higher than Exp 11 at the same load levels due to ztunnel processing overhead. The delta quantifies the mesh tax.

---

## Experiment 13 — Noisy-Neighbor Injection into DeathStarBench

**Section 4 | Real Workload Validation — Main Result**

### What It Is

A synthetic HTTP service (`svc-noisy`) is deployed to `worker-0` alongside DSB, forcing it to share the same ztunnel instance as the victim services. DSB runs at a fixed, stable load (50/100/100 RPS). `svc-noisy` is then ramped up to create shared-ztunnel contention. This experiment reproduces the interference phenomenon from Exp 3 in a realistic, multi-service environment.

### Victim Pinning Cases

Three cases test different victim services on `worker-0`:

| Case | Pinned Service | Affected Endpoints |
|------|---------------|-------------------|
| A | `social-graph-service` | compose-post, home-timeline |
| B | `user-service` | compose-post, user-timeline |
| C | `media-service` | compose-post only |

### Interference Modes

| Mode | Description |
|------|-------------|
| `sustained-ramp` | 0 → 700 RPS in 100-step increments, 60 seconds per step |
| `burst` | 200 ms at 1500 RPS / 800 ms quiet, repeating at 1 Hz |
| `churn` | 75 new connections/sec + TLS renegotiation at 200 RPS baseline |

### Running

```bash
cd Section_4_Real_Workload_Validation/Experiment13

# Deploy DSB with ambient mode (same as Exp 12) + inject svc-noisy on worker-0
make setup

# Primary: Case A, sustained-ramp (8 load levels × 3 reps = 24 trials, ~2 hours)
make run CASE=A MODE=sustained-ramp

# Cases B and C
make run CASE=B MODE=sustained-ramp
make run CASE=C MODE=sustained-ramp

# Burst and churn modes
make run CASE=A MODE=burst
make run CASE=A MODE=churn
```

### Analysis

```bash
make analyze            # produces amplification.csv
make figures            # generates all publication figures
```

**`amplification.csv` columns:** `case, mode, noisy_rps, endpoint, metric, baseline_ms, noisy_ms, amplification_x, goodput_drop_pct`

### Key Outputs

| Figure | Description |
|--------|-------------|
| `amplification_curves.png` | Per-endpoint P99 amplification ratio vs noisy_rps for Cases A/B/C |
| `amplification_heatmap.png` | Case × endpoint × load level amplification grid |
| `mode_vs_baseline.png` | P99 distributions: sustained vs burst vs churn |
| `percentile_comparison_700rps.png` | Full percentile fan at peak noisy load |
| `three_exp_amplification.png` | Exp 11 vs 12 vs 13 amplification comparison |
| `three_exp_radar.png` | Radar chart of all three experiments across metrics |
| `mesh_tax_bars.png` | Mesh-tax and noisy-neighbor-tax decomposition |
| `overhead_waterfall.png` | Cumulative overhead waterfall: no-mesh → ambient → interference |

---

## Methodology Notes

### Fixed-QPS Load Generation

All experiments use **open-loop load generators** (Fortio with `--qps`, wrk2 with `-R` and `-D exp`). This avoids coordinated omission: the load generator does not slow its request rate when the system is under stress, so percentile measurements reflect real-world latency, not just the latency the system was able to report.

### Warm-Cluster Methodology

For Exp 11–13, the social graph is initialized once before the measurement phase. Repetitions run back-to-back with no namespace teardown between runs. This captures steady-state performance (MongoDB/Redis caches warm, JVM JIT-compiled, kernel conntrack tables populated) rather than cold-start behavior.

### eBPF Instrumentation (Exp 4)

The eBPF approach requires no changes to application code or Istio configuration. kprobes attach to kernel TCP functions; uprobes attach to ztunnel's compiled binary. Scheduler tracepoints (`sched_switch`, `sched_wakeup`) provide worker-thread occupancy independently of CPU utilization counters, enabling the CPU-latency decoupling proof.

### Reproducibility

- All Kubernetes resources are fully declarative YAML; no manual `kubectl` steps are needed during experiments
- Cleanup scripts are idempotent: re-running `make clean && make setup` produces an identical starting state
- Analysis runs inside a versioned Docker image so figure generation is reproducible regardless of host Python version
- Raw data directories are timestamped and never overwritten; a new run creates a new `run_NNN` directory

---

## Common Makefile Targets

| Target | Description |
|--------|-------------|
| `make setup` | Label nodes, deploy workloads, verify readiness |
| `make check` | Verify cluster prerequisites (Istio, bpftrace, load-gen tools) |
| `make run` | Execute a single experiment run |
| `make run-seq N=5` | Execute N sequential repetitions (warm-cluster) |
| `make analyze` | Run Python analysis pipeline, produce CSVs |
| `make figures` | Generate all publication figures |
| `make build` | Build Docker analysis image |
| `make clean` | Tear down all experiment resources |

---

## Git Hygiene

Raw data files, PDFs, and virtual environments are excluded from version control:

```
# .gitignore (key entries)
results/raw/
*.pdf
.venv/
__pycache__/
```

Generated figures in `results/plots_lvl*/` and `results/tables/` are committed only after analysis is finalized.
