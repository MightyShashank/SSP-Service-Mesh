# Three-Way Comparison: Exp11 vs Exp12 vs Exp13

> **What this is:** A direct, side-by-side comparison of all three experiment tiers in the SSP study:
> - **Exp11** — Plain Kubernetes (NO service mesh) → true zero-overhead baseline
> - **Exp12** — Istio Ambient Mesh (mTLS via ztunnel, no sidecars) → mesh-only overhead
> - **Exp13** — Noisy Neighbor (Ambient Mesh + competing workload on shared ztunnel) → interference effect

This folder contains the scripts, figures, and tables that quantify:
1. **Mesh Tax**: How much latency Istio Ambient adds on top of plain K8s (Exp12 − Exp11)
2. **Noisy Overhead**: How much the noisy neighbor amplifies latency on top of Ambient alone (Exp13 − Exp12)
3. **Total Cost**: The full overhead from bare K8s to a noisy-neighbor Ambient deployment (Exp13 − Exp11)

---

## Data Sources

| Experiment | Input file | Description |
|------------|-----------|-------------|
| Exp11 | `../../Experiment11/results/tables/summary.csv` | 5-run median latency, plain K8s (no mesh) |
| Exp12 | `../../Experiment12/results/tables/summary.csv` | 6-run median latency, Istio Ambient (no noisy) |
| Exp13 | `../../results/tables/amplification.csv` | Per-case/mode/RPS amplification data |

---

## How to Run

From the **Experiment13 root directory**:

```bash
cd /home/appu/projects/SSP\ Project/Section_4_Real_Workload_Validation/Experiment13

# Activate venv (has numpy, matplotlib, pandas)
source .venv/bin/activate

# Run with default noisy RPS = 700
bash comparisons_Exp11_Exp12_Exp13/run_comparison_three.sh

# Run with specific noisy RPS point (e.g. 400 or 1000)
bash comparisons_Exp11_Exp12_Exp13/run_comparison_three.sh 400
```

The script runs `compare_three.py` and writes all outputs **inside this folder**:
- `tables/` → CSV result tables
- `figures/` → PNG + PDF figures

### Direct python call (for debugging):
```bash
source .venv/bin/activate
python3 comparisons_Exp11_Exp12_Exp13/compare_three.py \
  --exp11  "../Experiment11/results/tables/summary.csv" \
  --exp12  "../Experiment12/results/tables/summary.csv" \
  --amp13  "results/tables/amplification.csv" \
  --output "comparisons_Exp11_Exp12_Exp13" \
  --noisy-rps 700
```

---

## Output Files

### Tables (`tables/`)

| File | Description |
|------|-------------|
| `three_way_latency.csv` | Full P50/P75/P90/P99/P99.9/P99.99 for all 3 experiments + overhead columns |
| `mesh_tax.csv` | Exp11 vs Exp12 only — delta in ms and % per endpoint/metric |
| `cumulative_overhead.csv` | P50/P99/P99.99 — mesh tax %, noisy tax %, total tax % all-in-one |

### Figures (`figures/`)

| File | Description |
|------|-------------|
| `three_way_percentile_bars.png/.pdf` | **Main comparison figure** — grouped bar chart: Exp11 (green) / Exp12 (blue) / Exp13 (red) at P50, P99, P99.99 per endpoint |
| `overhead_waterfall.png/.pdf` | Stacked bar: plain K8s base → + mesh overhead → + noisy overhead, with % annotations |
| `mesh_tax_bars.png/.pdf` | Mesh overhead only (Exp12 vs Exp11) as % increase per endpoint/percentile |
| `three_exp_amplification.png/.pdf` | Line chart: amplification ×(vs Exp11 baseline) vs noisy RPS, with Exp12 fixed line and Exp13 curve |
| `three_exp_radar.png/.pdf` | Polar radar: P50/P99/P99.99 across all 3 endpoints for all 3 experiments simultaneously |

---

## How to Read the Results

All three experiments share the same cluster, workload rates, and pod placement:
- **compose-post**: 50 RPS target
- **home-timeline**: 100 RPS target
- **user-timeline**: 100 RPS target

### Actual observed data
*(Data will be populated in the tables/ directory after running the scripts with the freshly collected warm-cluster results from Exp11 and Exp12).*

### Color coding (consistent across all figures)
| Color | Experiment | Meaning |
|-------|-----------|---------|
| 🟢 Green | Exp11 (plain K8s) | No mesh — true zero-overhead baseline |
| 🔵 Blue | Exp12 (Ambient) | Istio Ambient mTLS — mesh tax only |
| 🔴 Red | Exp13 (noisy @ N RPS) | Noisy neighbor on shared ztunnel — interference |



## Prerequisites

- Exp11 `summary.csv` must exist (run `make analyze` in Experiment11 first)
- Exp12 `summary.csv` must exist (run `make analyze` in Experiment12 first)
- Exp13 `amplification.csv` must exist (run Exp13 analysis pipeline first)
- Python venv with `numpy`, `matplotlib` active (`.venv/` in Experiment13 root)

---

*Part of SSP T2 2025 — Section 4: Real Workload Validation*
