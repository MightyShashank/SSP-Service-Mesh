# Experiment 13 — Variant: Isolated ztunnel Control

> **Section 4.2 — Real Workload Validation**
> This is the **control experiment** for Experiment 13. `svc-noisy` is pinned to `worker-1`, giving it a **separate ztunnel instance** from the DSB victim services on `worker-0`. All load rates, durations, and analysis steps are identical to Experiment 13.

**→ Read [`WHAT_IT_IS.md`](WHAT_IT_IS.md) first to understand what changes and why.**

---

## Overview

**One change from Experiment 13:** `svc-noisy` and `svc-noisy-backend` are pinned to **worker-1** instead of worker-0.

**DSB victim services (social-graph, user-service, etc.) remain on worker-0 — unchanged.**

This means noisy traffic flows through `ztunnel-worker1` and DSB victim traffic flows through `ztunnel-worker0`. They **do not share a ztunnel**. Expected result: DSB tail latency shows no significant amplification regardless of noisy RPS.

| Case | Victim tier | Noisy node | Shared ztunnel? |
|------|-------------|------------|-----------------|
| **A** | social-graph → worker-0 | worker-1 | ❌ No |
| **B** | user-service → worker-0 | worker-1 | ❌ No |
| **C** | media-service → worker-0 | worker-1 | ❌ No |

| Mode | Description |
|------|-------------|
| `sustained-ramp` | 0 → 700 RPS in 100-step increments (60s each) |
| `burst` | 200ms @ 1500 RPS / 800ms quiet, 1 Hz |
| `churn` | 75 new conns/s + TLS renegotiation at 200 RPS |

---

## Complete Execution Order

All steps below are run from the **Variant root directory**:
```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment13/Variant
```

---

### Step 1 — Create Python virtual environment

```bash
bash scripts/utils/setup-venv.sh
source .venv/bin/activate
python3 -c "import matplotlib, numpy, pandas; print('[OK] venv ready')"
```

Or:
```bash
make setup
make check-venv
```

> ⚠️ **Always activate the venv** before running any `python3` command:
> `source .venv/bin/activate`

---

### Step 2 — Verify cluster and DSB are running

```bash
kubectl cluster-info
kubectl get pods -n dsb-exp

# Confirm social-graph is still on worker-0 (unchanged from Exp 13)
kubectl get pods -n dsb-exp -o wide | grep social-graph
```

Or:
```bash
make verify
```

---

### Step 3 — Deploy svc-noisy on worker-1

> **This is the key difference from Experiment 13.**
> The `configs/noisy-neighbor/svc-noisy-deploy.yaml` in this folder pins both `svc-noisy` and `svc-noisy-backend` to `worker-1`.

```bash
# If you ran Experiment 13, remove its worker-0 noisy pods first:
kubectl delete -f ../configs/noisy-neighbor/svc-noisy-deploy.yaml --ignore-not-found
sleep 5

# Deploy the Variant's noisy pods (worker-1 placement)
kubectl apply -f configs/noisy-neighbor/svc-noisy-deploy.yaml

kubectl wait --for=condition=Ready pod -l app=svc-noisy         -n dsb-exp --timeout=120s
kubectl wait --for=condition=Ready pod -l app=svc-noisy-backend -n dsb-exp --timeout=120s

# CRITICAL: Verify svc-noisy lands on worker-1, NOT worker-0
kubectl get pods -n dsb-exp -o wide | grep svc-noisy
# Expected: both pods on default-pool-ssp-157a7771fb89 (worker-1)
# NOT on:   default-pool-ssp-11b2c93c3e14   (worker-0 — that would be Exp 13!)
```

Or:
```bash
make noisy
```

---

### Step 4 — Quick smoke test (one trial)

**Available Arguments:**

1. `--case` (The Victim Case — victim service remains pinned to worker-0):
   * **`A`**: Targets `social-graph` (affects `compose-post` and `home-timeline`).
   * **`B`**: Targets `user-service` (affects `compose-post` and `user-timeline`).
   * **`C`**: Targets `media-service` (affects `compose-post` only).

2. `--mode` (The Noisy Neighbor Interference Pattern):
   * **`sustained-ramp`**: Constant flat load set by `--noisy-rps`, but goes through **worker-1's** ztunnel.
   * **`burst`**: 200ms bursts at 1500 RPS / 800ms quiet at 1 Hz.
   * **`churn`**: 75 new connections/sec with full TLS renegotiation, 200 RPS steady.

3. `--noisy-rps`: Integer RPS value for `sustained-ramp` single-point runs.

```bash
source .venv/bin/activate

bash scripts/run/run-experiment.sh --case A --mode sustained-ramp --noisy-rps 200

ls data/raw/case-A/sustained-ramp/trial_001/
# Expected files (identical structure to Experiment 13):
#   compose-post.txt    home-timeline.txt    user-timeline.txt
#   noisy-load.txt      ztunnel-top.txt      pod-cpu.txt
#   node-cpu.txt        pod-placement.txt    run-metadata.txt
```

**Sanity check after smoke test:**
```bash
# P99.9 of compose-post should be CLOSE TO BASELINE (~826ms)
# NOT the 1.5–2.5× spike seen in Experiment 13 at 200 RPS noisy
grep "99.900%" data/raw/case-A/sustained-ramp/trial_001/compose-post.txt

# Verify noisy pods are on worker-1 in pod-placement.txt
grep svc-noisy data/raw/case-A/sustained-ramp/trial_001/pod-placement.txt
```

Or:
```bash
make smoke
```

---

### Step 5 — Run Case A: Sustained Ramp (primary control experiment)

Generates the control counterpart to Experiment 13 Plots A, B, C, G, H. Allow ~2 hours.

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

### Step 6 — Run Cases B and C

No Helm changes needed for the Variant — noisy pods are always on worker-1 regardless of victim case. Just run the sweeps:

```bash
source .venv/bin/activate

bash scripts/run/run-sustained-ramp.sh --case B --reps 3
kubectl rollout status deployment -n dsb-exp

bash scripts/run/run-sustained-ramp.sh --case C --reps 3
```

Or:
```bash
make run-ramp CASE=B REPS=3
make run-ramp CASE=C REPS=3
```

> Note: Unlike Experiment 13, **no Helm node re-pinning is needed between cases** for the Variant. The noisy placement is always worker-1; only the output label (`--case`) changes.

---

### Step 7 — Run Burst and Churn modes

```bash
source .venv/bin/activate

for i in 1 2 3; do
  bash scripts/run/run-experiment.sh --case A --mode burst
  sleep 120
done

for i in 1 2 3; do
  bash scripts/run/run-experiment.sh --case A --mode churn
  sleep 120
done
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
    python3 src/parser/wrk2_parser.py \
      --runs-dir "$dir" \
      --output   "data/processed/csv/case-${case}/${mode}/"
  done
done

ls data/processed/csv/case-A/sustained-ramp/
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
  --baseline ../../../Experiment12/results/tables/summary.csv \
  --data     data/processed/csv/ \
  --output   results/tables/amplification.csv

cat results/tables/amplification.csv
```

Or:
```bash
make amplification
```

---

### Step 11 — Generate figures

```bash
source .venv/bin/activate

python3 src/plotting/exp13_plots.py \
  --data        data/processed/csv/ \
  --traces-dir  data/processed/csv/ \
  --ztunnel-dir data/raw/ \
  --baseline    ../../../Experiment12/results/tables/summary.csv \
  --output      results/figures/
```

Or:
```bash
make figures
```

---

## Full Workflow via Make

```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment13/Variant

make setup
make verify
make noisy          # ← Deploys to WORKER-1 (the key difference)
make smoke          # Check P99.9 stays near baseline
make run-ramp CASE=A REPS=3
make run-ramp CASE=B REPS=3
make run-ramp CASE=C REPS=3
make run-burst CASE=A
make run-churn CASE=A
make analyze
make figures
```

---

## Expected Results

The amplification factors should be **near 1.0×** across all RPS levels — proving that the interference seen in Experiment 13 is attributable to ztunnel sharing, not general cluster load.

| Endpoint | Baseline P99.9 | At 700 RPS noisy (Variant) | Amplification |
|----------|---------------|---------------------------|---------------|
| compose-post | ~826 ms | ~850–1000 ms | **~1.0–1.2×** |
| home-timeline | ~1.16s | ~1.2–1.4s | **~1.0–1.2×** |
| user-timeline | ~1.09s | ~1.1–1.3s | **~1.0–1.2×** |

Compare these directly against Experiment 13's results (5–9× amplification at 700 RPS). The delta between the two experiments isolates the ztunnel contention effect.

---

## Directory Layout

```
Variant/
├── WHAT_IT_IS.md                    ← Read this first: explains the one change
├── Makefile                         ← All targets (same as Exp13, adjusted paths)
├── requirements.txt                 ← Python deps (identical to Exp13)
├── configs/
│   ├── wrk2/
│   │   ├── rates.env                ← DSB rates (identical to Exp13)
│   │   ├── noisy-neighbor.lua
│   │   ├── compose-post.lua
│   │   ├── read-home-timeline.lua
│   │   └── read-user-timeline.lua
│   └── noisy-neighbor/
│       ├── modes.env                ← Ramp/burst/churn params (identical to Exp13)
│       └── svc-noisy-deploy.yaml   ← *** CHANGED: worker-1 instead of worker-0 ***
├── data/
│   ├── raw/case-A/sustained-ramp/trial_NNN/   ← Same structure as Exp13
│   └── processed/csv/
├── results/
│   ├── tables/amplification.csv
│   └── figures/
├── scripts/                         ← Identical scripts to Exp13
│   ├── run/
│   │   ├── run-experiment.sh
│   │   ├── run-sustained-ramp.sh
│   │   ├── run-noisy-burst.sh
│   │   └── run-noisy-churn.sh
│   ├── metrics/
│   │   ├── capture-ztunnel-cpu-top.sh
│   │   └── collect-traces.sh
│   ├── deploy/
│   ├── cleanup/
│   └── utils/
│       └── setup-venv.sh
└── src/                             ← Identical analysis/plotting code to Exp13
    ├── parser/
    │   ├── wrk2_parser.py
    │   └── trace_parser.py
    ├── analysis/
    │   └── amplification.py
    └── plotting/
        └── exp13_plots.py
```

---

## Cleanup

```bash
# Remove svc-noisy from worker-1
make clean-noisy

# Full teardown
make clean
```

---

*Experiment 13 Variant — Isolated ztunnel Control · SSP T2 2025*
