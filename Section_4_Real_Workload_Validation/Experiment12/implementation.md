# Implementation Plan — Experiment 12: DeathStarBench Baseline Characterization

## Overview

This experiment establishes a **trustworthy, reproducible performance baseline** for DeathStarBench (DSB) Social Network running under Istio Ambient Mode with stock ztunnel and **no** co-located noisy neighbor.

This baseline is the reference point for all subsequent Section 4 experiments (Exp 13–15). Without a rigorous baseline, any interference claim is unfalsifiable. Every number in the paper's Table~4 (expected baseline latencies) must trace back to raw data collected here.

**Experiment Goal (from paper §4.3.1):**
> Establish a trustworthy performance baseline for DSB Social Network running under Istio ambient mode with stock ztunnel and no co-located noisy neighbor.

**Section in paper:** Section 4 — Real-Workload Validation, Experiment 12 (§4.3.1)

---

## Cluster Configuration (Actual)

> **Note:** The cluster used is different from the original document's KIND 3-node setup. Actual cluster:

| Property | Value |
|----------|-------|
| Cluster type | Managed Kubernetes (3 bare nodes) |
| Nodes | 3 worker nodes (no separate control-plane node) |
| Node hardware | 4 vCPUs, 8 GB RAM per node |
| Node names | `default-pool-ssp-11b2c93c3e14`, `default-pool-ssp-157a7771fb89`, `default-pool-ssp-865907b54154` |
| Kubernetes version | v1.35.2 |
| OS | Ubuntu 22.04 LTS |
| Istio version | 1.23.x (Ambient mode) |
| ztunnel | Rust-based (not Envoy-based) |
| CNI | Flannel (or cluster default CNI) |

**Node role assignment for this experiment:**

| Node | Role |
|------|------|
| `default-pool-ssp-11b2c93c3e14` | **worker-0** — Hosts DSB victim-tier pods + ztunnel (primary experiment node) |
| `default-pool-ssp-157a7771fb89` | **worker-1** — Hosts remaining DSB services (mid-tier, databases, Jaeger) |
| `default-pool-ssp-865907b54154` | **load-gen** — Hosts wrk2 load-generator pods (cpuset-isolated) |

> The load generator is a dedicated pod on the third node (not a bare control-plane), isolated via `cpuset` resource limits to avoid interference with Kubernetes system processes.

---

## Services Under Test

| Service | Role | Node | Load |
|---------|------|------|------|
| social-graph, user-service, media-service, url-shorten, text-filter | **Victim tiers** | `worker-0` | Receives DSB traffic |
| compose-post, post-storage, home-timeline, user-timeline, nginx-frontend, Jaeger, MongoDB×3, Redis×2 | **Mid-tier** | `worker-1` | Receives DSB traffic |
| wrk2 (3 instances) | **Load generator** | `load-gen` | Drives DSB endpoints |

**Endpoints driven simultaneously:**

| Endpoint | RPS | wrk2 Script |
|----------|-----|-------------|
| `/wrk2-api/post/compose` | 200 RPS | `social-network/compose-post.lua` |
| `/wrk2-api/home-timeline/read` | 300 RPS | `social-network/read-home-timeline.lua` |
| `/wrk2-api/user-timeline/read` | 300 RPS | `social-network/read-user-timeline.lua` |

**Operating point:** 60–70% of saturation throughput on 4-vCPU worker nodes (updated from doc's 2-vCPU). A pre-run saturation sweep identifies the knee of the P99 vs. throughput curve.

---

## Metrics to Collect

Per the experiment spec (§4.3.1):

1. **End-to-end latency histograms:** P50, P95, P99, P99.9, P99.99 at the load generator
2. **Goodput** (successful RPS) and **error rate** (%) per endpoint
3. **ztunnel CPU utilization:** per-thread, per-second via `/proc/{pid}/task/{tid}/stat`
4. **ztunnel RSS:** via `/proc/{pid}/smaps_rollup`
5. **Per-hop Jaeger span latency** for `compose-post` traces (Jaeger sampling: 100% during baseline)
6. **Network throughput** on `worker-0`: nethogs per-pod

---

## Graphs to Produce

1. **Latency-throughput sweep:** P99 vs. offered load (RPS) for each endpoint — identifies saturation knee
2. **Latency CDF (log-x):** End-to-end latency CDF for `compose-post` at 200 RPS — three lines: No Mesh, Istio Sidecar, Istio Ambient
3. **Jaeger flame chart:** Mean per-hop latency breakdown for a `compose-post` trace at baseline

---

## Expected Results

From paper Table 4 (values are for 2-vCPU nodes; 4-vCPU nodes should have lower latency, treat these as upper-bound targets):

| Endpoint | RPS | P50 (ms) | P99 (ms) | P99.9 (ms) | P99.99 (ms) |
|----------|-----|----------|----------|-----------|------------|
| compose-post | 200 | 3.8 | 15.2 | 34.0 | 62.0 |
| read-home-timeline | 300 | 2.5 | 10.1 | 23.8 | 46.5 |
| read-user-timeline | 300 | 1.7 | 7.2 | 16.0 | 32.0 |

**Key acceptance criterion:** ztunnel CPU attributable to DSB traffic < 20% of the 4-vCPU budget at the 60% utilization operating point.

---

## Experimental Protocol

- **Warm-up:** 60 seconds (discarded)
- **Measured run:** 180 seconds
- **Repetitions:** 5 independent repetitions, each with fresh pod restarts and database re-initialization
- **Reporting:** Median across repetitions for percentile values; 95% CI via bootstrap resampling (N=10,000)
- **Run validity:** Run-to-run CV must be < 5% on P50; runs exceeding this are flagged and repeated

---

## Folder Structure

```
Experiment12/
├── implementation.md               ← THIS FILE
├── folder_Structure.md             ← High-level tree overview (pre-existing)
├── README.md                       ← Quick-start guide
├── .gitignore
├── Makefile                        ← make deploy / make run / make analyze / make clean
├── requirements.txt                ← Python deps (pandas, matplotlib, scipy, etc.)
│
├── configs/
│   ├── kind/                       ← NOT USED (actual managed cluster, not KIND)
│   │   └── (omit or leave empty)
│   │
│   ├── kubernetes/
│   │   ├── namespace.yaml          ← mesh-exp namespace with istio.io/dataplane-mode: ambient
│   │   ├── resourcequotas.yaml     ← Optional: quotas for load-gen node
│   │   ├── priorityclasses.yaml    ← Optional: high-priority for victim tiers
│   │   └── node-labels.sh          ← Label nodes for deterministic scheduling
│   │
│   ├── istio/
│   │   ├── install-ambient.yaml    ← Istio ambient install values (if not already installed)
│   │   ├── mesh-config.yaml        ← MeshConfig: telemetry, tracing, mesh settings
│   │   ├── telemetry.yaml          ← Telemetry API config for Jaeger tracing
│   │   ├── peer-authentication.yaml← mTLS STRICT mode for mesh-exp namespace
│   │   └── waypoint-optional.yaml  ← (Not used in this experiment — L7 only if needed)
│   │
│   ├── deathstarbench/
│   │   └── social-network/
│   │       ├── base/               ← Official DSB Social-Network Helm/Kustomize base
│   │       │   ├── helm-values-ambient.yaml     ← DSB Helm values tuned for ambient mesh
│   │       │   ├── helm-values-sidecar.yaml     ← DSB Helm values for sidecar baseline
│   │       │   └── helm-values-nomesh.yaml      ← DSB Helm values for no-mesh baseline
│   │       │
│   │       ├── placement/
│   │       │   ├── worker0-affinity.yaml        ← nodeAffinity: victim tiers → worker-0
│   │       │   ├── worker1-affinity.yaml        ← nodeAffinity: mid-tier → worker-1
│   │       │   └── loadgen-affinity.yaml        ← nodeAffinity: wrk2 pods → load-gen node
│   │       │
│   │       └── init/
│   │           ├── init-social-graph.sh         ← Runs socfb-Reed98 graph init script
│   │           └── socfb-Reed98.txt             ← Facebook ego-network dataset (963 users)
│   │
│   ├── wrk2/
│   │   ├── compose-post.lua        ← wrk2 Lua script for /wrk2-api/post/compose
│   │   ├── read-home-timeline.lua  ← wrk2 Lua script for /wrk2-api/home-timeline/read
│   │   ├── read-user-timeline.lua  ← wrk2 Lua script for /wrk2-api/user-timeline/read
│   │   ├── rates.env               ← RPS targets: COMPOSE_RPS=200, HOME_RPS=300, USER_RPS=300
│   │   └── saturation-sweep.env   ← RPS sweep range for pre-run knee identification
│   │
│   └── observability/
│       ├── jaeger-values.yaml      ← Jaeger all-in-one on worker-1, sampling 100%
│       ├── prometheus-values.yaml  ← Prometheus scrape configs
│       └── grafana-dashboards/     ← Pre-built dashboards (optional)
│
├── scripts/
│   ├── deploy/
│   │   ├── deploy-setup.sh         ← End-to-end deploy: cluster labels + Istio + DSB + observability
│   │   ├── deploy-cluster.sh       ← (Managed cluster: just verify connectivity + node labels)
│   │   ├── deploy-istio-ambient.sh ← Install/verify Istio Ambient on cluster
│   │   ├── deploy-observability.sh ← Deploy Jaeger + Prometheus on worker-1
│   │   ├── deploy-dsb.sh           ← Deploy DSB Social-Network via Helm with placement overlays
│   │   ├── init-graph.sh           ← Initialize socfb-Reed98 social graph in MongoDB
│   │   ├── wait-until-ready.sh     ← Wait for all DSB pods to be Running + Ready
│   │   └── verify-deployment.sh    ← Verify pod placement, ztunnel presence, Jaeger, wrk2
│   │
│   ├── run/
│   │   ├── run-experiment.sh       ← Master orchestrator (all 5 repetitions, all endpoints)
│   │   ├── run-saturation-sweep.sh ← Pre-run latency-throughput sweep to find knee
│   │   ├── run-baseline-compose-post.sh    ← wrk2 for compose-post (200 RPS, 180s)
│   │   ├── run-baseline-home-timeline.sh   ← wrk2 for read-home-timeline (300 RPS, 180s)
│   │   ├── run-baseline-user-timeline.sh   ← wrk2 for read-user-timeline (300 RPS, 180s)
│   │   ├── run_parallel_endpoints.sh       ← Launches all 3 wrk2 instances in parallel
│   │   ├── run_sequential_experiments.sh   ← Runs N full experiment repetitions sequentially
│   │   ├── warmup.sh               ← 60s warm-up traffic (discarded)
│   │   └── timestamp-run.sh        ← Records run metadata (start/end time, run ID, config hash)
│   │
│   ├── metrics/
│   │   ├── capture-ztunnel-stats.sh        ← Per-thread CPU via /proc/{pid}/task/{tid}/stat
│   │   ├── capture-ztunnel-rss.sh          ← RSS via /proc/{pid}/smaps_rollup
│   │   ├── capture-k8s-stats.sh            ← kubectl top pod/node snapshots
│   │   ├── capture-node-stats.sh           ← Node-level: nethogs, iostat, vmstat
│   │   ├── capture-prometheus-snapshot.sh  ← Prometheus API snapshot for ztunnel metrics
│   │   ├── collect-traces.sh               ← Pull Jaeger traces via Jaeger HTTP API
│   │   └── sync-logs.sh                    ← Rsync results from worker nodes to local
│   │
│   ├── cleanup/
│   │   ├── cleanup.sh              ← Full teardown: DSB + Istio + labels (nuclear option)
│   │   ├── cleanup-workloads.sh    ← Delete DSB deployments only (keep Istio)
│   │   ├── cleanup-istio.sh        ← Remove Istio CRDs and Daemonsets
│   │   ├── cleanup-cluster.sh      ← Remove node labels + reset scheduling constraints
│   │   └── cleanup-deploy-setup.sh ← Idempotent: cleanup then redeploy (used by sequential runner)
│   │
│   └── utils/
│       ├── check-prereqs.sh        ← Verify wrk2, helm, kubectl, jq, python3 are available
│       ├── print-config.sh         ← Print all environment variables for a run
│       ├── label-nodes.sh          ← Label worker-0, worker-1, load-gen nodes
│       ├── kubectl-safe.sh         ← kubectl wrapper with retry logic
│       ├── retry.sh                ← Generic retry helper
│       └── archive-run.sh          ← Tar.gz a completed run directory for archival
│
├── workloads/
│   ├── profiles/
│   │   ├── paper-baseline.env      ← COMPOSE_RPS=200, HOME_RPS=300, USER_RPS=300
│   │   ├── saturation-sweep.env    ← RPS_MIN=50, RPS_MAX=600, RPS_STEP=50
│   │   ├── low-load.env            ← 50/100/100 RPS (smoke test)
│   │   └── high-load.env           ← 300/450/450 RPS (above saturation, for sweep)
│   │
│   ├── schedules/
│   │   ├── mixed-balanced.yaml     ← All 3 endpoints simultaneously (default for Exp12)
│   │   └── compose-post-only.yaml  ← Single endpoint (for saturation sweep)
│   │
│   └── request-bodies/
│       ├── compose-post.json       ← Sample POST body for compose-post
│       ├── user-ids.txt            ← User IDs from socfb-Reed98 for Lua scripts
│       └── media-ids.txt           ← Media IDs for media-service tests
│
├── data/
│   ├── raw/
│   │   ├── run_001/
│   │   │   ├── compose-post.json          ← wrk2 JSON output (--latency flag)
│   │   │   ├── home-timeline.json
│   │   │   ├── user-timeline.json
│   │   │   ├── ztunnel-cpu.txt            ← /proc capture during run
│   │   │   ├── ztunnel-rss.txt
│   │   │   ├── jaeger-traces.json         ← Collected from Jaeger API
│   │   │   ├── node-nethogs.txt           ← Network throughput
│   │   │   └── run-metadata.txt           ← Timestamps, config hash, git commit
│   │   ├── run_002/
│   │   ├── run_003/
│   │   ├── run_004/
│   │   └── run_005/
│   │
│   ├── processed/
│   │   ├── csv/                           ← Per-endpoint per-run latency CSVs
│   │   ├── parquet/                       ← Parquet format for large datasets
│   │   └── summaries/                     ← Aggregated statistics across runs
│   │
│   └── metadata/
│       ├── hardware-info.txt              ← lscpu, free -h, uname -a on worker nodes
│       ├── software-versions.txt          ← Istio, ztunnel, wrk2, DSB Helm chart versions
│       └── git-commit.txt                 ← Git hash of DSB and experiment repo
│
├── results/
│   ├── figures/
│   │   ├── latency-cdf/
│   │   │   ├── compose-post-cdf.pdf       ← Fig: CDF comparison (No Mesh, Sidecar, Ambient)
│   │   │   ├── home-timeline-cdf.pdf
│   │   │   └── user-timeline-cdf.pdf
│   │   │
│   │   ├── tail-percentiles/
│   │   │   ├── percentile-bars.pdf        ← P50/P99/P99.9/P99.99 bar chart per endpoint
│   │   │   └── percentile-table.csv       ← Machine-readable version of Table 4
│   │   │
│   │   ├── throughput/
│   │   │   ├── saturation-sweep-compose.pdf   ← P99 vs RPS latency-throughput sweep
│   │   │   ├── saturation-sweep-home.pdf
│   │   │   └── saturation-sweep-user.pdf
│   │   │
│   │   ├── ztunnel-cpu/
│   │   │   └── ztunnel-cpu-utilization.pdf    ← Per-thread CPU over time
│   │   │
│   │   └── traces/
│   │       └── jaeger-flamechart-compose.pdf  ← Per-hop latency breakdown
│   │
│   ├── tables/
│   │   ├── summary.csv             ← Experiment 12 main results table (all endpoints, all runs)
│   │   └── variance.csv            ← CV, CI, run-to-run variance per metric
│   │
│   └── reports/
│       ├── run_001_report.md       ← Auto-generated per-run report
│       └── final_baseline_report.md ← Final combined report for paper
│
├── notebooks/
│   ├── analyze_latency.ipynb       ← Latency percentile analysis + CDF plots
│   ├── analyze_variance.ipynb      ← Run-to-run variance, CV computation, CI bootstrap
│   ├── plot_tail_latency.ipynb     ← Generate paper-quality tail latency figures
│   └── generate-paper-figures.ipynb ← Master notebook: all paper figures for Exp12
│
├── src/
│   ├── parser/
│   │   ├── wrk2_parser.py          ← Parse wrk2 --latency JSON/text output
│   │   ├── prom_parser.py          ← Parse Prometheus metrics snapshots
│   │   └── trace_parser.py         ← Parse Jaeger trace JSON, extract per-hop spans
│   │
│   ├── analysis/
│   │   ├── stats.py                ← Percentile computation, bootstrap CI
│   │   ├── ci.py                   ← 95% CI via bootstrap resampling (N=10,000)
│   │   └── percentiles.py          ← P50/P99/P99.9/P99.99 extraction helpers
│   │
│   └── plotting/
│       ├── latency_plots.py        ← CDF plots, percentile bar charts
│       ├── cpu_plots.py            ← ztunnel CPU time-series plots
│       ├── saturation_plots.py     ← Latency-throughput sweep plots
│       └── report_plots.py         ← Combined report figure generation
│
└── ci/
    ├── smoke-test.sh               ← Quick connectivity + wrk2 sanity check
    ├── lint.sh                     ← shellcheck + python lint
    └── reproducibility-run.sh      ← Full 5-run cycle for CI validation
```

---

## Implementation Phases

### Phase 0: Prerequisites and Environment Check

**Script:** `scripts/utils/check-prereqs.sh`

Verify all tools are available before touching the cluster:

```bash
# Tools required on local machine / load-gen node:
# - kubectl (connected to cluster)
# - helm (v3.x)
# - wrk2 (compiled from source, pinned at load-gen node)
# - python3 + pip (for analysis)
# - jq (for JSON parsing)
# - git (for DSB repo checkout)
# - ssh access to worker nodes (for /proc metrics collection)
```

**Cluster pre-checks:**
- `kubectl cluster-info` — verify connectivity
- Verify all 3 nodes are `Ready` (`kubectl get nodes`)
- Verify Istio Ambient is installed (`kubectl get pods -n istio-system | grep ztunnel`)
- Verify ztunnel DaemonSet has a pod on **worker-0** and **worker-1**

---

### Phase 1: Node Labeling and Placement

**Script:** `scripts/utils/label-nodes.sh` + `configs/kubernetes/node-labels.sh`

Label all three nodes for deterministic scheduling:

```bash
# worker-0: hosts victim tiers (social-graph, user-service, etc.)
kubectl label node default-pool-ssp-11b2c93c3e14 role=worker-0 exp=dsb-victim --overwrite

# worker-1: hosts mid-tier services (compose-post, nginx, Jaeger, MongoDB, Redis)
kubectl label node default-pool-ssp-157a7771fb89 role=worker-1 exp=dsb-midtier --overwrite

# load-gen: hosts wrk2 load generator pods
kubectl label node default-pool-ssp-865907b54154 role=load-gen exp=dsb-loadgen --overwrite
```

**Verification:**
```bash
kubectl get nodes --show-labels | grep -E "worker-0|worker-1|load-gen"
```

---

### Phase 2: Cluster Setup — Namespace and Istio

**Script:** `scripts/deploy/deploy-istio-ambient.sh`

```bash
# Create experiment namespace with Ambient Mesh enabled
kubectl apply -f configs/kubernetes/namespace.yaml
# namespace.yaml sets: istio.io/dataplane-mode: ambient

# Verify ztunnel is running on both worker nodes
kubectl get pods -n istio-system -o wide | grep ztunnel
```

`configs/kubernetes/namespace.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dsb-exp
  labels:
    istio.io/dataplane-mode: ambient
```

---

### Phase 3: Deploy DeathStarBench Social Network

**Script:** `scripts/deploy/deploy-dsb.sh`

#### 3.1 — Clone and Configure DSB

```bash
# Clone DSB if not present
git clone https://github.com/delimitrou/DeathStarBench.git /opt/dsb

# Install via Helm with ambient-mode values + placement overlays
helm upgrade --install social-network /opt/dsb/socialNetwork/helm-chart \
  --namespace dsb-exp \
  --values configs/deathstarbench/social-network/base/helm-values-ambient.yaml \
  --values configs/deathstarbench/social-network/placement/worker0-affinity.yaml \
  --values configs/deathstarbench/social-network/placement/worker1-affinity.yaml
```

#### 3.2 — Placement Rules

`configs/deathstarbench/social-network/placement/worker0-affinity.yaml`:
```yaml
# Pin victim-tier services to worker-0 (sharing ztunnel with noisy neighbor in Exp13)
# Services: social-graph, user-service, media-service, url-shorten, text-filter
global:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: role
          operator: In
          values: [worker-0]
```

`configs/deathstarbench/social-network/placement/worker1-affinity.yaml`:
```yaml
# Pin mid-tier services to worker-1
# Services: compose-post, post-storage, home-timeline, user-timeline,
#           nginx-frontend, Jaeger, MongoDB×3, Redis×2
```

#### 3.3 — Deploy Observability Stack

**Script:** `scripts/deploy/deploy-observability.sh`

```bash
# Jaeger all-in-one on worker-1 (100% sampling for baseline runs)
helm upgrade --install jaeger jaegertracing/jaeger \
  --namespace observability \
  -f configs/observability/jaeger-values.yaml

# Prometheus (optional, for ztunnel metrics)
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace observability \
  -f configs/observability/prometheus-values.yaml
```

---

### Phase 4: Social Graph Initialization

**Script:** `scripts/deploy/init-graph.sh`

This must run **after** all DSB pods are ready:

```bash
# Initialize socfb-Reed98 Facebook ego-network (963 users, 18,812 edges)
# This establishes realistic follower graph density
cd /opt/dsb/socialNetwork
python3 scripts/init_social_graph.py \
  --graph=socfb-Reed98 \
  --ip=$(kubectl get svc nginx-web-server -n dsb-exp -o jsonpath='{.spec.clusterIP}') \
  --port=8080
```

**Why this matters:**
- Without the social graph, `read-home-timeline` returns empty timelines (no fan-out)
- Graph density controls read fan-out depth, which affects critical-path latency
- Must be re-initialized before every repetition to ensure identical starting state

---

### Phase 5: Pre-Run Saturation Sweep

**Script:** `scripts/run/run-saturation-sweep.sh`

Before running the 5 baseline repetitions, identify the saturation knee for each endpoint:

```bash
# Sweep compose-post from 50 to 600 RPS in steps of 50
for RPS in 50 100 150 200 250 300 350 400 450 500 550 600; do
  ../wrk2/wrk -D exp -t 4 -c 50 -d 60s -L \
    -s configs/wrk2/compose-post.lua \
    http://${NGINX_IP}:8080/wrk2-api/post/compose -R ${RPS} \
    > data/raw/saturation-sweep/compose-post-${RPS}rps.txt
  sleep 30  # cooldown between sweep points
done
```

**Goal:** Confirm that 200/300/300 RPS is at 60–70% of saturation for each endpoint. If not, adjust `rates.env` before the main 5-run baseline.

---

### Phase 6: Warmup

**Script:** `scripts/run/warmup.sh`

```bash
# 60 seconds warm-up at target RPS — discarded from analysis
# Sends traffic to all 3 endpoints simultaneously
# Ensures JIT compilation, connection pool warm-up, cache warming
../wrk2/wrk -D exp -t 2 -c 50 -d 60s \
  -s configs/wrk2/compose-post.lua \
  http://${NGINX_IP}:8080/wrk2-api/post/compose -R 200 &

../wrk2/wrk -D exp -t 2 -c 50 -d 60s \
  -s configs/wrk2/read-home-timeline.lua \
  http://${NGINX_IP}:8080/wrk2-api/home-timeline/read -R 300 &

../wrk2/wrk -D exp -t 2 -c 50 -d 60s \
  -s configs/wrk2/read-user-timeline.lua \
  http://${NGINX_IP}:8080/wrk2-api/user-timeline/read -R 300 &

wait
```

---

### Phase 7: Main Experiment Execution

**Master script:** `scripts/run/run-experiment.sh`

This script orchestrates a single complete experiment repetition:

```
1. Pre-checks (pods ready, wrk2 available, Jaeger up, NGINX_IP known)
2. Re-initialize social graph (fresh DB state)
3. Start background metrics collection:
   a. ztunnel CPU poller (scripts/metrics/capture-ztunnel-stats.sh)
   b. ztunnel RSS poller (scripts/metrics/capture-ztunnel-rss.sh)
   c. Jaeger trace collection (background)
   d. nethogs on worker-0
4. Run warmup (60s, discarded)
5. Run 3 wrk2 instances in parallel (180s measurement window):
   a. compose-post at 200 RPS
   b. read-home-timeline at 300 RPS
   c. read-user-timeline at 300 RPS
6. Stop all background collection
7. Save all outputs to data/raw/run_NNN/
8. Record run metadata (timestamp, config hash, git commit)
9. Collect Jaeger traces via HTTP API
10. Cooldown (wait for CPU < 40% on worker nodes)
```

**Sequential repetition runner:** `scripts/run/run_sequential_experiments.sh`

```bash
# Run N complete experiment repetitions back to back
# Each repetition: cleanup-deploy-setup + run-experiment
./run_sequential_experiments.sh 5
```

---

### Phase 8: Metrics Collection Details

#### 8.1 — ztunnel CPU per-thread

**Script:** `scripts/metrics/capture-ztunnel-stats.sh`

```bash
ZTUNNEL_PID=$(kubectl exec -n istio-system $(kubectl get pod -n istio-system -l app=ztunnel \
  -o jsonpath="{.items[?(@.spec.nodeName=='default-pool-ssp-11b2c93c3e14')].metadata.name}") \
  -- cat /proc/1/status | grep Pid | awk '{print $2}')

# Poll per-thread CPU stats every 1 second
while true; do
  for TID in $(ls /proc/${ZTUNNEL_PID}/task/); do
    cat /proc/${ZTUNNEL_PID}/task/${TID}/stat
  done
  sleep 1
done >> data/raw/run_NNN/ztunnel-cpu.txt
```

#### 8.2 — ztunnel RSS

**Script:** `scripts/metrics/capture-ztunnel-rss.sh`

```bash
# Poll /proc/{pid}/smaps_rollup every 5 seconds
while true; do
  echo "=== $(date) ==="
  cat /proc/${ZTUNNEL_PID}/smaps_rollup | grep Rss
  sleep 5
done >> data/raw/run_NNN/ztunnel-rss.txt
```

#### 8.3 — Jaeger Trace Collection

**Script:** `scripts/metrics/collect-traces.sh`

```bash
JAEGER_IP=$(kubectl get svc jaeger-query -n observability -o jsonpath='{.spec.clusterIP}')

# Collect all traces for compose-post service during measurement window
curl "http://${JAEGER_IP}:16686/api/traces?service=compose-post&limit=10000&start=${START_TIME_US}&end=${END_TIME_US}" \
  > data/raw/run_NNN/jaeger-traces.json
```

---

### Phase 9: Cleanup

**Script:** `scripts/cleanup/cleanup-deploy-setup.sh`

Idempotent cleanup + redeploy — used between repetitions:

```bash
#!/bin/bash
set -euo pipefail

NAMESPACE="dsb-exp"

log() { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

# ===== STEP 0: Pre-checks =====
log "Checking kubectl connectivity..."
kubectl cluster-info > /dev/null || fail "kubectl not connected"

# ===== STEP 1: Cleanup =====
log "Deleting DSB workloads..."
helm uninstall social-network -n "${NAMESPACE}" 2>/dev/null || warn "DSB not installed, skipping"

log "Deleting namespace..."
if kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1; then
  kubectl delete namespace "${NAMESPACE}"
  kubectl wait --for=delete ns/"${NAMESPACE}" --timeout=180s \
    || warn "Namespace deletion taking longer than expected"
else
  warn "Namespace does not exist, skipping deletion"
fi

# ===== STEP 2: Redeploy =====
log "Recreating namespace..."
kubectl apply -f ../configs/kubernetes/namespace.yaml

log "Deploying DSB Social Network..."
bash ./deploy/deploy-dsb.sh

log "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n "${NAMESPACE}" --timeout=300s \
  || fail "Pods did not become ready within 5 minutes"

# ===== STEP 3: Verify Placement =====
log "Verifying victim-tier pod placement on worker-0..."
SOCIAL_GRAPH_NODE=$(kubectl get pod -n "${NAMESPACE}" -l app=social-graph -o jsonpath='{.items[0].spec.nodeName}')
if [[ "$SOCIAL_GRAPH_NODE" != "default-pool-ssp-11b2c93c3e14" ]]; then
  fail "social-graph NOT on worker-0 → experiment INVALID"
fi
echo "✔ social-graph → worker-0 ($SOCIAL_GRAPH_NODE)"

# ===== STEP 4: Verify ztunnel =====
log "Verifying ztunnel on worker-0..."
ZTUNNEL_POD=$(kubectl get pods -n istio-system -o wide | \
  awk '$7 == "default-pool-ssp-11b2c93c3e14" && /ztunnel/ {print $1}')
if [[ -z "$ZTUNNEL_POD" ]]; then
  fail "No ztunnel on worker-0 → experiment INVALID"
fi
echo "✔ ztunnel on worker-0 → $ZTUNNEL_POD"

# ===== STEP 5: Re-initialize Social Graph =====
log "Initializing socfb-Reed98 social graph..."
bash ./deploy/init-graph.sh || fail "Social graph initialization failed"

# ===== FINAL SUMMARY =====
log "Environment ready ✅"
echo "Namespace: ${NAMESPACE}"
echo "DSB: deployed + graph initialized"
echo "ztunnel: $ZTUNNEL_POD on worker-0"
echo "Status: READY FOR EXPERIMENT"
```

---

### Phase 10: Analysis and Visualization

**Scripts:** `src/parser/`, `src/analysis/`, `src/plotting/`

#### 10.1 — Parse wrk2 Output

`src/parser/wrk2_parser.py`:
- Parses wrk2 `--latency` text output
- Extracts: P50, P75, P90, P95, P99, P99.9, P99.99, throughput (req/s), errors
- Outputs: CSV per endpoint per run

#### 10.2 — Aggregate Across Repetitions

`src/analysis/stats.py`:
- Computes median across 5 runs per percentile per endpoint
- Computes 95% CI via bootstrap resampling (N=10,000)
- Flags runs where CV > 5% on P50

#### 10.3 — Generate Figures

`src/plotting/latency_plots.py` — **Figure 1: Latency CDF**
```python
# Log-x CDF of compose-post end-to-end latency
# Three lines: No Mesh, Istio Sidecar, Istio Ambient
# X-axis: latency (ms, log scale)
# Y-axis: fraction of requests ≤ latency
```

`src/plotting/saturation_plots.py` — **Figure 2: Latency-Throughput Sweep**
```python
# P99 vs offered load (RPS) for each endpoint
# X-axis: RPS, Y-axis: P99 latency (ms)
# Identify knee: point where P99 begins to rise sharply
```

`src/plotting/latency_plots.py` — **Figure 3: Jaeger Flame Chart**
```python
# Mean per-hop latency for compose-post call chain
# X-axis: span duration (ms)
# Stacked bars per service hop
# Source: parsed Jaeger JSON via trace_parser.py
```

---

## Key Script: `run-experiment.sh`

Full annotated structure:

```bash
#!/bin/bash
set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
NAMESPACE="dsb-exp"
WORKER_0="default-pool-ssp-11b2c93c3e14"
WORKER_1="default-pool-ssp-157a7771fb89"
LOAD_GEN_NODE="default-pool-ssp-865907b54154"

RESULTS_DIR="../data/raw"
RUN_ID=$(date +"%Y%m%d_%H%M%S")
PHASE_DIR="$RESULTS_DIR/run_$(ls $RESULTS_DIR | wc -l | awk '{printf "%03d", $1+1}')"
mkdir -p "$PHASE_DIR"

# Load RPS targets from profile
source ../workloads/profiles/paper-baseline.env
# COMPOSE_RPS=200, HOME_RPS=300, USER_RPS=300

DURATION="180s"
WARMUP_DURATION="60s"
TIMELINE_FILE="$RESULTS_DIR/experiment_timeline.txt"

# wrk2 settings: -t 2 (2 threads, matches available cores on load-gen pod)
# -c 50 (50 connections, sized for open-loop semantics at these rates)
# -D exp (exponential inter-arrival, open-loop mode — prevents coordinated omission)
WRK2_THREADS=2
WRK2_CONNS=50
WRK2_BINARY="../wrk2/wrk"

# ==============================
# HELPERS
# ==============================
log()  { echo -e "\n[INFO] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

cooldown() {
  log "Cooling down system..."
  sleep 60
  if ! kubectl top node > /dev/null 2>&1; then
    log "Metrics API not available — using fixed 60s cooldown"
    return
  fi
  for i in {1..20}; do
    CPU=$(kubectl top node 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $3}' || echo "")
    if [[ -z "$CPU" ]]; then sleep 5; continue; fi
    if [ "$CPU" -lt 40 ]; then tick "System stabilized (CPU < 40%)"; return; fi
    log "Waiting... CPU=${CPU}%"
    sleep 10
  done
  log "Cooldown timeout reached, continuing..."
}

# ==============================
# PRE-CHECKS
# ==============================
log "Verifying cluster state..."

kubectl cluster-info > /dev/null || fail "kubectl not connected"

NGINX_IP=$(kubectl get svc nginx-web-server -n "$NAMESPACE" \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null) \
  || fail "nginx-web-server service not found in namespace $NAMESPACE"
log "DSB nginx IP: $NGINX_IP"

# Verify victim-tier on worker-0
SOCIAL_GRAPH_NODE=$(kubectl get pod -n "$NAMESPACE" -l app=social-graph \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null) || fail "social-graph pod not found"
[[ "$SOCIAL_GRAPH_NODE" == "$WORKER_0" ]] || fail "social-graph is NOT on worker-0"
tick "social-graph on worker-0"

# Discover ztunnel PID on worker-0 (via exec into ztunnel pod)
ZTUNNEL_POD=$(kubectl get pods -n istio-system -o wide | \
  awk -v node="$WORKER_0" '$0 ~ "ztunnel" && $7 == node {print $1}')
[[ -n "$ZTUNNEL_POD" ]] || fail "No ztunnel pod on worker-0"
tick "ztunnel pod: $ZTUNNEL_POD"

# Verify Jaeger is up
JAEGER_IP=$(kubectl get svc jaeger-query -n observability \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null) || warn "Jaeger not found — skipping traces"

# ==============================
# START BACKGROUND METRICS
# ==============================
log "Starting background metrics collection..."

# ztunnel CPU poller (runs in background via kubectl exec)
bash ../scripts/metrics/capture-ztunnel-stats.sh "$WORKER_0" "$PHASE_DIR/ztunnel-cpu.txt" &
PID_CPU=$!

# ztunnel RSS poller
bash ../scripts/metrics/capture-ztunnel-rss.sh "$WORKER_0" "$PHASE_DIR/ztunnel-rss.txt" &
PID_RSS=$!

tick "Background metrics running (PIDs: $PID_CPU, $PID_RSS)"

# ==============================
# WARMUP (60s, discarded)
# ==============================
log "Running warmup (${WARMUP_DURATION})..."
bash ../scripts/run/warmup.sh "$NGINX_IP" "$WARMUP_DURATION"
tick "Warmup complete"

RUN_START=$(timestamp)

# ==============================
# MAIN MEASUREMENT RUN (180s)
# ==============================
log "Starting 3 wrk2 instances in parallel (${DURATION})..."

$WRK2_BINARY -D exp -t $WRK2_THREADS -c $WRK2_CONNS -d $DURATION -L \
  -s configs/wrk2/compose-post.lua \
  "http://${NGINX_IP}:8080/wrk2-api/post/compose" -R $COMPOSE_RPS \
  > "$PHASE_DIR/compose-post.txt" 2>&1 &
PID_COMPOSE=$!

$WRK2_BINARY -D exp -t $WRK2_THREADS -c $WRK2_CONNS -d $DURATION -L \
  -s configs/wrk2/read-home-timeline.lua \
  "http://${NGINX_IP}:8080/wrk2-api/home-timeline/read" -R $HOME_RPS \
  > "$PHASE_DIR/home-timeline.txt" 2>&1 &
PID_HOME=$!

$WRK2_BINARY -D exp -t $WRK2_THREADS -c $WRK2_CONNS -d $DURATION -L \
  -s configs/wrk2/read-user-timeline.lua \
  "http://${NGINX_IP}:8080/wrk2-api/user-timeline/read" -R $USER_RPS \
  > "$PHASE_DIR/user-timeline.txt" 2>&1 &
PID_USER=$!

wait $PID_COMPOSE || warn "compose-post wrk2 exited with error"
wait $PID_HOME    || warn "home-timeline wrk2 exited with error"
wait $PID_USER    || warn "user-timeline wrk2 exited with error"

RUN_END=$(timestamp)
tick "Measurement window complete"

# ==============================
# STOP BACKGROUND METRICS
# ==============================
kill $PID_CPU $PID_RSS 2>/dev/null || true
wait $PID_CPU $PID_RSS 2>/dev/null || true
tick "Background metrics stopped"

# ==============================
# COLLECT SYSTEM SNAPSHOTS
# ==============================
log "Collecting system snapshots..."
kubectl top pod -n "$NAMESPACE" > "$PHASE_DIR/pod-cpu.txt" || true
kubectl top pod -n istio-system > "$PHASE_DIR/ztunnel-kubectl-top.txt" || true
kubectl top node > "$PHASE_DIR/node-cpu.txt" || true

# ==============================
# COLLECT JAEGER TRACES
# ==============================
if [[ -n "${JAEGER_IP:-}" ]]; then
  log "Collecting Jaeger traces..."
  bash ../scripts/metrics/collect-traces.sh "$JAEGER_IP" "$PHASE_DIR/jaeger-traces.json" || warn "Jaeger trace collection failed"
fi

# ==============================
# RECORD METADATA
# ==============================
{
  echo "Run ID: $RUN_ID"
  echo "Start: $RUN_START"
  echo "End: $RUN_END"
  echo "Duration: $DURATION"
  echo "Endpoints: compose-post=${COMPOSE_RPS}RPS, home-timeline=${HOME_RPS}RPS, user-timeline=${USER_RPS}RPS"
  echo "Worker-0: $WORKER_0"
  echo "ztunnel pod: $ZTUNNEL_POD"
  echo "Jaeger IP: ${JAEGER_IP:-N/A}"
  echo "Config hash: $(git -C .. rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
} > "$PHASE_DIR/run-metadata.txt"

# ==============================
# APPEND TO TIMELINE FILE
# ==============================
{
  echo ""
  echo "# Run $RUN_ID"
  echo "Start: $RUN_START"
  echo "End: $RUN_END"
  echo "Phase: $PHASE_DIR"
} >> "$TIMELINE_FILE"

# ==============================
# FINAL SUMMARY
# ==============================
log "Experiment run COMPLETE ✅"
echo "========== RUN SUMMARY =========="
echo "Run ID: $RUN_ID"
echo "Phase Dir: $PHASE_DIR"
echo "Duration: $DURATION"
echo "Endpoints:"
echo "  compose-post    → $COMPOSE_RPS RPS"
echo "  home-timeline   → $HOME_RPS RPS"
echo "  user-timeline   → $USER_RPS RPS"
echo "=================================="
```

---

## Key Script: `run_sequential_experiments.sh`

```bash
#!/bin/bash
# Usage: ./run_sequential_experiments.sh <num_repetitions>
# Runs N full experiment cycles: cleanup-deploy-setup → run-experiment
# Each cycle reinitializes the social graph for fresh DB state

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <num_repetitions>"
  exit 1
fi

NUM_RUNS=$1

log()  { echo -e "\n[INFO] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }
fail() { echo -e "\n[ERROR] $1"; exit 1; }

log "Running $NUM_RUNS experiment repetitions..."

for i in $(seq 1 $NUM_RUNS); do
  echo -e "\n======================================"
  echo "[REPETITION $i / $NUM_RUNS]"
  echo "======================================"

  log "Running cleanup and fresh deploy..."
  bash ./cleanup/cleanup-deploy-setup.sh || fail "Cleanup-deploy failed on rep $i"
  tick "Environment ready for rep $i"

  log "Running experiment rep $i..."
  bash ./run/run-experiment.sh || fail "Experiment failed on rep $i"
  tick "Repetition $i completed"

  if [ "$i" -lt "$NUM_RUNS" ]; then
    log "Cooldown before next repetition..."
    sleep 120   # 2 minute cooldown between repetitions
  fi
done

log "ALL $NUM_RUNS REPETITIONS COMPLETED ✅"
echo "Results in: data/raw/"
echo "Run: make analyze to process results"
```

---

## Addressing Reviewer Criticisms (from Paper §4.3.1)

### "Your rates are too low."
The 200/300/300 RPS rates are calibrated to 60–70% of saturation on 4-vCPU worker nodes (higher capacity than the doc's 2-vCPU). The saturation sweep (`run-saturation-sweep.sh`) confirms the operating point is below the knee. Running at saturation conflates proxy interference with application-level overload.

### "Why five repetitions?"
DSB exhibits run-to-run variance from MongoDB write-ahead logging and Redis eviction randomness. Five repetitions with fresh DB initialization reduce variance to < 5% CV on P50. We report the median with 95% CI via bootstrap.

### "Why 4-vCPU nodes instead of 2-vCPU?"
Our actual cluster has 4-vCPU nodes instead of the original 2-vCPU in the doc. This increases the available ztunnel budget, which shifts the saturation point. The saturation sweep identifies the actual knee. All expected latencies in this doc are **upper bounds**; actual results on 4-vCPU should be lower. This does not affect the paper's interference argument — the mechanism is scheduler-level, not CPU-saturation.

---

## Execution Checklist

### Pre-Run
- [ ] `kubectl get nodes` — all 3 nodes `Ready`
- [ ] `kubectl get pods -n istio-system | grep ztunnel` — ztunnel running on all nodes
- [ ] Node labels applied (`label-nodes.sh`)
- [ ] wrk2 binary available and tested on load-gen node
- [ ] Python env set up (`pip install -r requirements.txt`)
- [ ] DSB repo cloned at `/opt/dsb` (or configured path)
- [ ] Jaeger deployed and accessible

### Deploy
- [ ] `make deploy` or `bash scripts/deploy/deploy-setup.sh`
- [ ] Verify pod placement: `kubectl get pods -n dsb-exp -o wide`
- [ ] Verify ztunnel on worker-0: `kubectl get pods -n istio-system -o wide | grep ztunnel`
- [ ] Verify social graph initialized: curl nginx IP, check for non-empty timeline

### Pre-Measurement
- [ ] Run saturation sweep: `bash scripts/run/run-saturation-sweep.sh`
- [ ] Confirm 200/300/300 RPS is at < 80% of knee

### Measurement (5 repetitions)
- [ ] `bash scripts/run/run_sequential_experiments.sh 5`
- [ ] Monitor: `tail -f data/raw/experiment_timeline.txt`
- [ ] After each run: check CV on P50 — flag and repeat if CV > 5%

### Analysis
- [ ] `make analyze` — runs all parsers + stats scripts
- [ ] `make figures` — generates all 3 paper figures
- [ ] Review `results/tables/summary.csv` — compare to Table 4 in paper
- [ ] Review `results/tables/variance.csv` — verify CV < 5% on P50

### Done
- [ ] Archive: `bash scripts/utils/archive-run.sh`
- [ ] Update `data/metadata/hardware-info.txt` with actual node specs

---

## Expected Results Summary

| Endpoint | RPS | Expected P50 (ms) | Expected P99 (ms) | Expected P99.99 (ms) |
|----------|-----|--------------------|--------------------|-----------------------|
| compose-post | 200 | ≤ 3.8 | ≤ 15.2 | ≤ 62.0 |
| read-home-timeline | 300 | ≤ 2.5 | ≤ 10.1 | ≤ 46.5 |
| read-user-timeline | 300 | ≤ 1.7 | ≤ 7.2 | ≤ 32.0 |

> Values shown are upper bounds from 2-vCPU doc. Actual results on 4-vCPU nodes are expected to be **lower** due to increased ztunnel headroom.

**Key acceptance criteria:**
1. ztunnel CPU attributable to DSB traffic < 20% of 4-vCPU budget at operating point
2. Run-to-run CV < 5% on P50 for all endpoints
3. P99 vs. RPS curve shows no inflection below operating point (confirmed by saturation sweep)
4. Jaeger per-hop latency breakdown shows no single hop dominating (balanced call chain)

---

## Differences from Experiment 3 / Experiment 4

| Aspect | Experiment 3/4 (Sec 2) | Experiment 12 (Sec 4) |
|--------|------------------------|----------------------|
| Workload | Synthetic svc-a/svc-b (nginx/echo) | DeathStarBench Social Network (12 microservices) |
| Load generator | Fortio (inside cluster) | wrk2 open-loop (`-D exp`) pinned to dedicated node |
| Services | 2 | 12+ (social-graph, user, media, nginx, MongoDB×3, Redis×2, Jaeger...) |
| Node setup | Same-node placement (all on worker-1) | Split placement (victim tiers → worker-0, mid-tier → worker-1) |
| Noisy neighbor | Present (svc-b) | **ABSENT** — this is the clean baseline |
| Graph init | Not needed | Required (socfb-Reed98, 963 users) |
| Tracing | None | Jaeger full-trace (100% sampling) |
| Analysis | Stacked bar, latency decomposition | CDF, latency-throughput sweep, Jaeger flame chart |
| Repetitions | 3–5 (no strict CV requirement) | 5 with CV < 5% requirement on P50 |
| Key metric | Proxy queue delay component | Absolute tail latency per endpoint (paper Table 4) |
