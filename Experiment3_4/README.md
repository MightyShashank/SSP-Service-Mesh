
# Experiment 3: Istio Ambient Same-Node Communication

## Objective
Evaluate intra-node communication behavior under **Istio Ambient Mesh**, focusing on how a **shared node-level dataplane (ztunnel)** impacts latency under multi-service load.

---

## Core Hypothesis
When multiple services share the same **ztunnel (node-level proxy)**, contention in CPU and queueing resources leads to **tail latency amplification**, even if median latency remains stable.

---

## Key Design Choices

- **Namespace-level mesh enablement**
  - `istio.io/dataplane-mode=ambient`
  - Ensures automatic inclusion of all pods in mesh

- **Same-node pod placement**
  - Enforced via `nodeSelector`
  - Guarantees shared dataplane (same ztunnel instance)

- **Client inside cluster**
  - Eliminates external network noise
  - Ensures traffic originates within same dataplane context

- **Deterministic setup**
  - Fully declarative YAML + scripts
  - No manual steps

- **QPS-controlled load generation (Fortio)**
  - Fixed request rate instead of best-effort load
  - Enables clean **load vs latency analysis**

---

## Repository Structure

- `cluster-setup/` → Infra assumptions (mesh enablement, node control)
- `workloads/` → Kubernetes manifests (svc-a, svc-b, client)
- `traffic/` → Load generation scripts (**Fortio-based**)
- `scripts/` → One-click execution (deploy, cleanup, experiment run)
- `observability/` → Metrics + Prometheus queries
- `results/` → Raw + processed experiment outputs
- `analysis/` → Parsing + plotting scripts
- `docs/` → Experiment explanation (for reviewers)

---

## Setup
```bash
cd scripts
bash deploy.sh
```
This will:
- Create namespace with ambient mesh enabled.
- Label node for deterministic scheduling.
- Deploy:
    - svc-a (latency-sensitive).
    - svc-b (noisy workload).
    - client (traffic generator)
- Ensure all pods run on same node are on the same ztunnel. \\

The Script automatically verifies: \\
- Pod co-location (same node).
- ztunnel presence.
- Shared dataplane usage.


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

## After above experiment to collect results: Setup (Docker):
```bash
make build
make run RUN_ID=<RUN_ID>

# Then to clean do this:
make clean
```