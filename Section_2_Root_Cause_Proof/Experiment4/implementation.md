# Implementation Plan — Experiment 4: Latency Decomposition via eBPF

## Overview

This experiment establishes **causal evidence** that cross-service interference originates inside the shared proxy runtime (ztunnel) by decomposing end-to-end request latency into pipeline components and correlating queueing delay with proxy worker occupancy.

Unlike Experiment 3 (which observed interference from the outside using Fortio), Experiment 4 instruments **inside** the kernel and ztunnel binary using eBPF to pinpoint exactly *where* latency is being added.

---

## System Information

| Component | Value |
|-----------|-------|
| Kernel | `6.8.0-1053-gcp` |
| OS | Ubuntu 22.04 (Jammy) |
| bpftrace | `0.14.0-1` (installed) |
| Architecture | amd64 / GCP |

---

## Folder Structure

Mirrors Experiment 3 with the following additions/changes:

```
Experiment4/
├── .gitignore
├── Dockerfile
├── Makefile
├── README.md
├── requirements.txt
├── implementation.md            ← THIS FILE
│
├── cluster-setup/               # Same as Exp3 (namespace + node label + verify)
│   ├── namespace.yaml
│   ├── node-label.sh
│   └── verify.sh
│
├── workloads/                   # Same as Exp3 (svc-a, svc-b, client)
│   ├── svc-a-deployment.yaml
│   ├── svc-b-deployment.yaml
│   ├── services.yaml
│   └── client.yaml
│
├── config/                      # Experiment parameters per phase
│   ├── baseline.env
│   └── load-levels.env
│
├── ebpf/                        # ★ NEW — eBPF probes (core of this experiment)
│   ├── latency_decomp.bt        # kprobe/uprobe: 5-timestamp decomposition
│   ├── sched_occupancy.bt       # sched tracepoints: worker thread occupancy
│   ├── queue_delay.bt           # uprobe: proxy enqueue/dequeue delay
│   └── install-bpftrace.sh      # bpftrace installation helper
│
├── traffic/                     # Fortio load generation (simplified from Exp3)
│   ├── warmup.sh
│   └── load-generator.sh        # Parameterized: generates svc-A fixed + svc-B variable
│
├── scripts/                     # Orchestration scripts
│   ├── deploy-setup.sh
│   ├── cleanup.sh
│   ├── cleanup-deploy-setup.sh
│   ├── run-experiment.sh         # Master orchestrator (runs all phases + eBPF collection)
│   └── run_sequential_experiments.sh
│
├── analysis/                    # Python analysis & plotting
│   ├── analyze_lvl1.py          # Stacked latency breakdown + component histograms
│   ├── analyze_lvl2.py          # Proxy queue delay vs load + worker occupancy correlation
│   ├── analyze_lvl3.py          # HoL blocking timeline + decoupling plot
│   └── analyze_lvl4.py          # Baseline vs interference comparison (combined figure)
│
├── docs/                        # Experiment documentation
│   ├── experiment-design.md
│   ├── methodology.md
│   ├── architecture.md
│   └── threats-to-validity.md
│
├── results/                     # Output data
│   ├── raw/                     # Raw JSON + eBPF trace outputs
│   ├── processed/               # Parsed CSVs
│   ├── plots_lvl1/
│   ├── plots_lvl2/
│   ├── plots_lvl3/
│   └── plots_lvl4/
│
└── observability/               # (empty, reserved for Prometheus queries if needed)
```

### Key Structural Differences from Experiment 3

| Aspect | Experiment 3 | Experiment 4 |
|--------|-------------|-------------|
| Core data source | Fortio JSON output | eBPF traces (kprobe/uprobe/tracepoint) |
| New directory | — | `ebpf/` (bpftrace scripts) |
| Config files | `baseline.env`, `interference.env`, `load-rap.env` | `baseline.env`, `load-levels.env` |
| Traffic scripts | Separate per-phase scripts | Unified parameterized `load-generator.sh` |
| Load levels | 500, 1000, 2000, 4000 QPS | 0, 100, 500, 1000 RPS (per experiment spec) |
| Analysis scripts | General latency comparison | Latency decomposition, occupancy correlation, HoL detection |
| Plots produced | 4 types in lvl1 | 8 visualization types across 4 analysis levels |

---

## Implementation Phases

### Phase 1: Infrastructure Setup

**Goal:** Reuse the same cluster setup pattern from Experiment 3.

1. **`cluster-setup/namespace.yaml`** — Identical to Exp3 (`mesh-exp` namespace with `istio.io/dataplane-mode: ambient`)
2. **`cluster-setup/node-label.sh`** — Identical to Exp3 (label `ssp-worker-1` with `exp=mesh`)
3. **`cluster-setup/verify.sh`** — Identical to Exp3 (verify same-node placement + ztunnel)

### Phase 2: Workload Deployment

**Goal:** Deploy identical two-service workload from Experiment 3.

1. **`workloads/svc-a-deployment.yaml`** — Identical (nginx, latency-sensitive)
2. **`workloads/svc-b-deployment.yaml`** — Identical (http-echo, noisy neighbor)
3. **`workloads/services.yaml`** — Identical (both exposed on port 80)
4. **`workloads/client.yaml`** — Identical (Fortio pod, same node)

### Phase 3: eBPF Instrumentation (★ Core Differentiator)

**Goal:** Instrument ztunnel with bpftrace probes for latency decomposition.

> **Prerequisites:**
> - bpftrace 0.14.0 is already installed (`sudo apt policy bpftrace` confirms)
> - Kernel 6.8.0-1053-gcp supports kprobes, uprobes, and sched tracepoints
> - All eBPF scripts must run **on the worker node** (`ssp-worker-1`) with `sudo`

#### 3.1 — `ebpf/install-bpftrace.sh`
Install/verify bpftrace on the target node. Ensures:
- `bpftrace` binary is available
- Kernel headers are present (`linux-headers-$(uname -r)`)
- Required debugfs/tracefs mounted
- Smoke-tested with `tracepoint:syscalls:sys_enter_openat` (NOT `BEGIN`/`exit()` — see known bug below)
- Verifies all required probes: `kprobe:tcp_rcv_established`, `kretprobe:tcp_recvmsg`, `kprobe:tcp_sendmsg`, `tracepoint:sched:sched_switch`, `tracepoint:sched:sched_wakeup`

#### 3.2 — `ebpf/latency_decomp.bt`
**Five-timestamp latency decomposition per request:**

| Timestamp | Probe | Captures |
|-----------|-------|----------|
| $t_1$ | `kprobe:tcp_rcv_established` | Packet arrival at kernel TCP stack |
| $t_2$ | `kretprobe:tcp_recvmsg` (ztunnel PID-filtered) | Bytes delivered to ztunnel userspace |
| $t_3$ | Estimated via ztunnel function entry (uprobe if symbols available, else $t_2$ + kernel-to-user delta) | Request enters proxy pipeline |
| $t_4$ | Estimated via scheduler dispatch (ztunnel function, uprobe) | Request begins execution |
| $t_5$ | `kprobe:tcp_sendmsg` (ztunnel PID-filtered) | Response written to socket |

**Important bpftrace 0.14.0 limitations:**
- No `uprobe` on stripped Rust binaries (ztunnel is Rust). We will check for available symbols using `nm` or `readelf` on the ztunnel binary.
- **Fallback strategy:** If ztunnel symbols are stripped, we decompose using only kernel probes:
  - $t_1$: `kprobe:tcp_rcv_established` (filtered by ztunnel PID)
  - $t_2$: `kretprobe:tcp_recvmsg` (filtered by ztunnel PID)
  - $t_5$: `kprobe:tcp_sendmsg` (filtered by ztunnel PID)
  - $T_{internal} = t_5 - t_2$ captures total proxy processing time (queue + execution combined)
- **Symbol check script** embedded in `run-experiment.sh` to auto-detect and choose probe strategy

**Latency decomposition (with symbols):**
```
T_network     = t2 - t1
T_kernel_queue = t3 - t2
T_proxy_queue  = t4 - t3
T_execution    = t5 - t4
```

**Latency decomposition (fallback, without symbols):**
```
T_network       = t2 - t1
T_proxy_total   = t5 - t2   (queue + execution combined)
```

#### 3.3 — `ebpf/sched_occupancy.bt`
**Worker thread CPU occupancy via scheduler tracepoints:**

```
tracepoint:sched:sched_switch → tracks per-TID on-CPU / off-CPU time
```

- Filters by ztunnel worker thread TIDs (auto-discovered from `/proc/<pid>/task/`)
- Computes: `occupancy = on_cpu_time / (on_cpu_time + off_cpu_time)` per interval
- Outputs periodic (1s interval) occupancy percentages

#### 3.4 — `ebpf/queue_delay.bt`
**Proxy queue delay tracing:**

- If ztunnel has `enqueue`/`dequeue` symbols → use uprobes
- **Fallback:** Approximate queue delay from scheduler data (time between `sched_wakeup` and `sched_switch` for ztunnel threads)

### Phase 4: Traffic Generation

**Goal:** Run svc-A at fixed 100 RPS while ramping svc-B through `{0, 100, 500, 1000}` RPS.

#### 4.1 — `traffic/warmup.sh`
Same pattern as Exp3. Light warmup for both services.

#### 4.2 — `traffic/load-generator.sh`
Parameterized script:
```bash
./load-generator.sh <svc-a-qps> <svc-b-qps> <duration> <output-dir>
```
- svc-A: fixed at 100 RPS, `-c 10` connections
- svc-B: variable, `-c 100` connections

### Phase 5: Experiment Orchestration

**Goal:** `scripts/run-experiment.sh` coordinates everything.

#### Experiment Flow:
```
1. Pre-checks (pods, fortio, bpftrace, ztunnel PID)
2. Discover ztunnel PID and worker TIDs
3. Check ztunnel symbol availability (uprobe vs kprobe-only strategy)
4. Warmup
5. For each load_level in {0, 100, 500, 1000}:
   a. Start eBPF probes (background):
      - latency_decomp.bt
      - sched_occupancy.bt
      - queue_delay.bt
   b. Start Fortio traffic (svc-A fixed + svc-B at load_level)
   c. Wait for traffic completion
   d. Stop eBPF probes (SIGINT)
   e. Save all outputs to results/raw/<run_id>/<load_level>/
   f. Cooldown (60s + CPU check)
6. Collect system metrics (kubectl top)
7. Write timeline
```

### Phase 6: Analysis & Visualization

**Goal:** Generate the 8 visualizations specified in the experiment design.

#### `analysis/analyze_lvl1.py` — Latency Breakdown
1. **Stacked Latency Breakdown vs. Load** — Stacked bar chart of $T_{network}$, $T_{kernel\_queue}$, $T_{proxy\_queue}$, $T_{execution}$ across svc-B load levels
2. **Latency Component Distributions (Histograms)** — Log-scale histograms of each component at P50/P99/P99.99

#### `analysis/analyze_lvl2.py` — Correlation Analysis
3. **Proxy Queue Delay vs. svc-B Load** — Line graph (RPS on X, P99.99 queue delay on Y)
4. **Worker Occupancy vs. Queue Delay (Correlation Plot)** — Scatter/dual-axis time-series

#### `analysis/analyze_lvl3.py` — Deep Dive
5. **CPU Utilization vs. End-to-End Latency** — Line graph showing CPU–latency decoupling
6. **Head-of-Line Blocking Timeline** — Per-request timeline of enqueue/dequeue events

#### `analysis/analyze_lvl4.py` — Summary Comparison
7. **Queue Delay vs. Execution Time (Decoupling Plot)** — Scatter plot
8. **Baseline vs. Interference Comparison** — Side-by-side latency breakdown (0 RPS vs 1000 RPS)

### Phase 7: Documentation

Docs mirror Experiment 3 structure but describe eBPF methodology:
- `experiment-design.md` — Goal, hypothesis, eBPF probe strategy
- `methodology.md` — Timestamp collection, decomposition formulas, probe types
- `architecture.md` — ztunnel internal pipeline, eBPF attachment points
- `threats-to-validity.md` — Symbol availability, clock precision, probe overhead

---

## Critical Implementation Notes

### 1. ztunnel Binary Symbol Availability
The ztunnel binary (`/usr/local/bin/ztunnel` inside the ztunnel pod, or the host path) may or may not have debug symbols. This is critical for uprobe attachment.

**Detection approach in `run-experiment.sh`:**
```bash
# Find ztunnel binary path on host
ZTUNNEL_PID=$(pgrep -f ztunnel | head -1)
ZTUNNEL_BIN=$(readlink -f /proc/$ZTUNNEL_PID/exe)

# Check for symbols
if nm "$ZTUNNEL_BIN" 2>/dev/null | grep -q "queue::enqueue"; then
    PROBE_MODE="full"    # uprobes available
else
    PROBE_MODE="kprobe"  # fallback to kernel-only probes
fi
```

### 2. bpftrace PID Filtering
All probes must filter by ztunnel PID to avoid capturing unrelated traffic:
```
kprobe:tcp_rcv_established /pid == $ZTUNNEL_PID/ { ... }
```

### 3. eBPF Probe Overhead
- kprobes: ~100–500ns overhead per hit (negligible)
- uprobes: ~1–5μs overhead per hit (acceptable)
- sched tracepoints: ~200ns overhead (negligible)
- **Total probe overhead is well below measurement resolution**

### 4. Clock Synchronization
All timestamps use `nsecs` (monotonic clock from bpftrace). Since all probes run on the same host, no cross-node clock sync issues.

### 5. bpftrace 0.14.0-Specific Considerations
- Map operations: `@map[key] = value` syntax supported
- Histogram: `hist()` and `lhist()` supported
- `pid`, `tid`, `nsecs` builtins available
- `printf()` for structured output
- `interval:s:N` for periodic aggregation dumps

**⚠ CONFIRMED BUG: `BEGIN`/`exit()` broken in bpftrace 0.14.0 (Ubuntu 22.04)**

The Ubuntu 22.04 packaged bpftrace 0.14.0 binary is stripped, missing the `BEGIN_trigger` symbol:
```
ERROR: Could not resolve symbol: /proc/self/exe:BEGIN_trigger
```

- `BEGIN { ... }` and `END { ... }` probes **cannot attach**
- The `exit()` builtin also fails (it internally triggers END)
- **Workaround:** All `.bt` probes use `interval:s:N` for periodic output and are stopped via `SIGINT` (Ctrl+C or `kill -INT`). No `BEGIN`, `END`, or `exit()` calls are used anywhere in the probe files.
- kprobe, kretprobe, tracepoint probes all work correctly
- This does NOT affect experiment results — it only affects how probes start/stop

### 6. Running eBPF on the Node
eBPF probes run **directly on the GCP node** (`ssp-worker-1`), not inside a pod. The experiment script must SSH/exec to the node or run from a privileged DaemonSet.

**Recommended approach:** Run from master node via SSH:
```bash
ssh ssp-worker-1 "sudo bpftrace /path/to/probe.bt"
```
Or copy probes to the worker node and run locally.

---

## Execution Checklist

- [ ] Deploy infrastructure (`cluster-setup/`)
- [ ] Deploy workloads (`workloads/`)
- [ ] Verify bpftrace on worker node (`ebpf/install-bpftrace.sh`)
- [ ] Discover ztunnel PID and determine probe strategy
- [ ] Run experiment (`scripts/run-experiment.sh`)
- [ ] Analyze results (`make run-lvl1 RUN_ID=<id>`)
- [ ] Generate all 8 visualizations
- [ ] Repeat 3–5 times for statistical significance

---

## Expected Results Summary

| Load Level (svc-B RPS) | $T_{proxy\_queue}$ (P99.99) | Worker Occupancy | Dominant Component |
|:-:|:-:|:-:|:-:|
| 0 | < 50 μs | < 30% | $T_{execution}$ |
| 100 | ~100–500 μs | ~40% | $T_{execution}$ |
| 500 | ~1–5 ms | ~70% | $T_{proxy\_queue}$ |
| 1000 | > 10 ms | > 90% | $T_{proxy\_queue}$ (>90% of inflation) |

**Key Claim:** At P99.99, proxy queueing accounts for over 90% of total latency inflation.
