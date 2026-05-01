# Comparison: Exp12 vs Exp13

> **What this is:** A focused two-way comparison between the Istio Ambient Mesh baseline (Exp12) and the Noisy Neighbor interference experiment (Exp13).  
> This isolates the **ztunnel contention effect** — how much extra latency a competing workload (sharing the same ztunnel DaemonSet) causes on the victim application.

For the full **three-way comparison** (including plain K8s Exp11), see: [`../comparisons_Exp11_Exp12_Exp13/`](../comparisons_Exp11_Exp12_Exp13/README.md)

---

## Experiment Definitions

| Experiment | Description |
|------------|-------------|
| **Exp12** (baseline) | DeathStarBench Social Network running on Istio Ambient Mesh, **no noisy neighbor**. 6 runs. |
| **Exp13** (interference) | Same setup as Exp12, **plus a noisy neighbor** co-located on worker-0, sharing the ztunnel. Three cases (A/B/C), three traffic modes (burst/churn/sustained-ramp), multiple RPS levels. |

### Exp13 Cases
| Case | Noisy pod placement | Purpose |
|------|--------------------|---------| 
| **A** | Same node as victim services (worker-0) | Full ztunnel sharing — maximum interference |
| **B** | Different node (worker-1) | Cross-node interference — network path only |
| **C** | Dedicated isolated node (load-gen node) | Control — no ztunnel sharing |

---

## Data Sources

| File | Description |
|------|-------------|
| `../../Experiment12/results/tables/summary.csv` | Exp12 baseline: 6-run median latencies (P50 → P99.99) |
| `../../results/tables/amplification.csv` | Exp13: per-case/mode/RPS amplification data |

---

## How to Run

From the **Experiment13 root directory**:

```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment13

# Activate venv
source .venv/bin/activate

# Run with default noisy RPS = 700
bash comparisons_Exp12_Exp13/run_comparison.sh

# Run with specific noisy RPS point
bash comparisons_Exp12_Exp13/run_comparison.sh 400
```

### Direct python call:
```bash
source .venv/bin/activate
python3 comparisons_Exp12_Exp13/compare.py \
  --baseline "../Experiment12/results/tables/summary.csv" \
  --amp       "results/tables/amplification.csv" \
  --output    "comparisons_Exp12_Exp13" \
  --noisy-rps 700
```

---

## Output Files

### Tables (`tables/`)

| File | Description |
|------|-------------|
| `amplification_summary.csv` | Amplification ×factor at each noisy RPS level per endpoint/metric/case/mode |
| `percentile_comparison.csv` | Side-by-side: Exp12 baseline ms vs Exp13 noisy ms at the selected RPS level |
| `case_comparison.csv` | Exp13 Case A vs B vs C — isolates ztunnel-local vs cross-node vs control effects |

### Figures (`figures/`)

| File | Description |
|------|-------------|
| `amplification_curves.png/.pdf` | **Key figure** — amplification ×factor vs noisy RPS, all 3 cases overlaid per endpoint |
| `percentile_comparison_700rps.png/.pdf` | Bar chart: Exp12 vs Exp13 at 700 RPS — P50/P99/P99.99 per endpoint |
| `amplification_heatmap.png/.pdf` | Heatmap: endpoint × noisy RPS → amplification factor (Case A, sustained-ramp) |
| `mode_vs_baseline.png/.pdf` | Grouped bars: burst vs churn vs sustained-ramp for each endpoint |

---

## How to Read the Results

### Amplification factor
All `amplification_x` values are defined as:
```
amplification_x = noisy_latency_ms / exp12_baseline_ms
```
- `1.0` = no change vs baseline
- `2.0` = 2× worse than baseline (100% overhead)
- Values < 1.0 = better than baseline (scheduling variance)

### Exp12 Baseline (6-run medians, reference point for all figures):
| Endpoint | P50 | P99 | P99.99 |
|----------|-----|-----|--------|
| compose-post | 305ms | 894ms | 1150ms |
| home-timeline | 185ms | 755ms | 1000ms |
| user-timeline | 151ms | 638ms | 904ms |

### Key findings (Case A, sustained-ramp @ 700 RPS):
| Endpoint | Exp13 P99 | Amplification |
|----------|-----------|---------------|
| compose-post | 3560ms | **3.98×** |
| home-timeline | 4280ms | **5.67×** |
| user-timeline | varies | varies |

> The tail latency amplification at P99.99 under sustained noisy load demonstrates conclusive ztunnel-level interference: the shared ztunnel DaemonSet becomes a bottleneck when the noisy neighbor saturates its CPU/connection budget.

---

## Prerequisites

- Exp12 `summary.csv` must exist: run `make analyze` in Experiment12
- Exp13 `amplification.csv` must exist: run Exp13 analysis pipeline
- Python venv with `numpy`, `matplotlib` active (`.venv/` in Experiment13 root)

---

*Part of SSP T2 2025 — Section 4: Real Workload Validation*
