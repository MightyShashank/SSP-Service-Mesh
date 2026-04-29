
# Experiment 4: Latency Decomposition via eBPF

## Objective
Establish **causal evidence** that cross-service interference originates inside the shared proxy runtime (ztunnel) by decomposing end-to-end request latency into its constituent pipeline components, and correlating queueing delay with proxy worker occupancy.

---

## Core Hypothesis
Tail-latency amplification in ambient service meshes is caused by **queueing delays inside the shared proxy runtime**, not by network congestion, kernel buffering, or application-level effects. This is directly evidenced by a strong correlation between proxy queue delay and worker thread CPU occupancy.

---

## Key Design Choices

- **eBPF-based instrumentation**
  - kprobes for kernel-level TCP events
  - uprobes for ztunnel internal functions (if symbols available)
  - sched tracepoints for worker thread occupancy
  - Zero application modification required

- **Five-timestamp latency decomposition**
  - $t_1$: Packet arrival at kernel TCP stack
  - $t_2$: Bytes delivered to ztunnel userspace
  - $t_3$: Request enqueued into proxy service queue
  - $t_4$: Request dequeued and begins execution
  - $t_5$: Response written to socket

- **Same-node pod placement**
  - Enforced via `nodeSelector`
  - Ensures shared dataplane (same ztunnel instance)
  - Eliminates inter-node network effects

- **Worker occupancy correlation**
  - Per-thread scheduling statistics via eBPF sched tracepoints
  - Correlates queueing delay with CPU contention

- **LoadLevels for svc-B**
  - `{0, 100, 500, 1000}` RPS

---

## Repository Structure

- `cluster-setup/` → Infra (mesh enablement, node control)
- `workloads/` → Kubernetes manifests (svc-a, svc-b, client)
- `ebpf/` → eBPF/bpftrace probe scripts (**core of this experiment**)
- `traffic/` → Load generation scripts (Fortio-based)
- `scripts/` → One-click execution (deploy, cleanup, experiment run)
- `config/` → Experiment parameters
- `analysis/` → Parsing + plotting scripts (8 visualizations)
- `docs/` → Experiment documentation
- `results/` → Raw + processed experiment outputs
- `observability/` → Reserved for Prometheus queries

---

## Setup
```bash
cd scripts
bash deploy-setup.sh
```
This will:
- Create namespace with ambient mesh enabled.
- Label node for deterministic scheduling.
- Deploy:
    - svc-a (latency-sensitive, 100 RPS)
    - svc-b (noisy neighbor, 0–1000 RPS)
    - client (traffic generator)
- Ensure all pods run on same node sharing the same ztunnel.

The Script automatically verifies:
- Pod co-location (same node).
- ztunnel presence.
- Shared dataplane usage.

## Verify bpftrace
```bash
cd ebpf
bash install-bpftrace.sh
```

## Pure Cleanup (No Deploy)
```bash
chmod +x cleanup.sh
./cleanup.sh
```

## Cleanup and deploy (idempotent)
```bash
chmod +x cleanup-deploy-setup.sh
./cleanup-deploy-setup.sh
```

## Running the Experiments
```bash
chmod +x run-experiment.sh
./run-experiment.sh
```

## After experiment to analyze results (Docker):
```bash
make build

# Level 1: Stacked latency breakdown + component histograms
make run-lvl1 RUN_ID=<run_id>

# Level 2: Proxy queue delay vs load + worker occupancy correlation
make run-lvl2 RUN_ID=<run_id>

# Level 3: HoL blocking timeline + CPU-latency decoupling
make run-lvl3 RUN_ID=<run_id>

# Level 4: Summary comparison (baseline vs interference)
make run-lvl4 RUN_ID=<run_id>

# Cleanup:
make clean
```
