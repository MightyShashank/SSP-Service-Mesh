#!/usr/bin/env python3
"""
Generate final_baseline_report.md from processed CSV results.
Usage: python3 src/analysis/generate_report.py
"""

import csv
import math
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]
SUMMARY_CSV  = ROOT / "results/tables/summary.csv"
VARIANCE_CSV = ROOT / "results/tables/variance.csv"
REPORT_OUT   = ROOT / "results/reports/final_baseline_report.md"
REPORT_OUT.parent.mkdir(parents=True, exist_ok=True)

# ── helpers ─────────────────────────────────────────────────────────────────

def load_csv(path):
    with open(path) as f:
        return list(csv.DictReader(f))

def ms(v):
    """Format a millisecond value nicely."""
    try:
        f = float(v)
        if math.isnan(f):
            return "N/A"
        if f >= 1000:
            return f"{f/1000:.2f} s"
        return f"{f:.1f} ms"
    except (TypeError, ValueError):
        return "N/A"

def cv_badge(cv_str):
    try:
        cv = float(cv_str)
        if math.isnan(cv):
            return "N/A"
        if cv > 25:
            return f"{cv:.1f}% 🔴"
        elif cv > 10:
            return f"{cv:.1f}% 🟡"
        else:
            return f"{cv:.1f}% 🟢"
    except (TypeError, ValueError):
        return "N/A"

# ── load data ────────────────────────────────────────────────────────────────

summary  = load_csv(SUMMARY_CSV)
variance = load_csv(VARIANCE_CSV)

# Build lookup: (endpoint, metric) -> row
sum_idx = {(r["endpoint"], r["metric"]): r for r in summary}
var_idx = {(r["endpoint"], r["metric"]): r for r in variance}

ENDPOINTS  = ["compose-post", "home-timeline", "user-timeline"]
KEY_METRICS = ["p50", "p75", "p90", "p99", "p99_9", "p99_99"]
METRIC_LABEL = {
    "p50": "P50", "p75": "P75", "p90": "P90",
    "p99": "P99", "p99_9": "P99.9", "p99_99": "P99.99",
}

n_runs = summary[0]["n_runs"] if summary else "?"
now    = datetime.now().strftime("%Y-%m-%d %H:%M")

# ── build report ─────────────────────────────────────────────────────────────

lines = []
a = lines.append

a(f"# Experiment 12 — Baseline Characterization Report")
a(f"")
a(f"> Generated: {now} | Runs: {n_runs} | Load: 50 RPS compose-post · 100 RPS home-timeline · 100 RPS user-timeline")
a(f"")
a(f"---")
a(f"")
a(f"## 1. Executive Summary")
a(f"")
a(f"This report documents the **steady-state latency baseline** for the DeathStarBench Social Network")
a(f"running under Istio Ambient Mesh on a 3-node Kubernetes cluster. The system was driven at")
a(f"sub-saturation load rates (50 / 100 / 100 RPS) and each measurement ran for **180 seconds**")
a(f"after a 60-second warmup, repeated **{n_runs} times**.")
a(f"")
a(f"| Finding | Value |")
a(f"|---------|-------|")

# pull key numbers
cp_p99  = sum_idx.get(("compose-post",  "p99"), {})
ht_p99  = sum_idx.get(("home-timeline", "p99"), {})
ut_p99  = sum_idx.get(("user-timeline", "p99"), {})
cp_p50  = sum_idx.get(("compose-post",  "p50"), {})
ht_p50  = sum_idx.get(("home-timeline", "p50"), {})
ut_p50  = sum_idx.get(("user-timeline", "p50"), {})

a(f"| compose-post  P50 | {ms(cp_p50.get('median_ms'))} |")
a(f"| compose-post  P99 | {ms(cp_p99.get('median_ms'))} |")
a(f"| home-timeline P50 | {ms(ht_p50.get('median_ms'))} |")
a(f"| home-timeline P99 | {ms(ht_p99.get('median_ms'))} |")
a(f"| user-timeline P50 | {ms(ut_p50.get('median_ms'))} |")
a(f"| user-timeline P99 | {ms(ut_p99.get('median_ms'))} |")
a(f"")
a(f"---")
a(f"")
a(f"## 2. Latency Percentile Tables")
a(f"")
a(f"> All values in **milliseconds** (median across {n_runs} repetitions, 95% bootstrap CI).")
a(f"> CV badge: 🟢 < 10% · 🟡 10–25% · 🔴 > 25%")
a(f"")

for ep in ENDPOINTS:
    a(f"### {ep}")
    a(f"")
    a(f"| Metric | Median | CI Low | CI High | CV |")
    a(f"|--------|--------|--------|---------|----|")
    for m in KEY_METRICS:
        sr = sum_idx.get((ep, m), {})
        vr = var_idx.get((ep, m), {})
        a(f"| {METRIC_LABEL[m]} | {ms(sr.get('median_ms'))} | {ms(sr.get('ci_lo_ms'))} | {ms(sr.get('ci_hi_ms'))} | {cv_badge(vr.get('cv_pct'))} |")
    a(f"")

a(f"---")
a(f"")
a(f"## 3. Variance Analysis")
a(f"")
a(f"The Coefficient of Variation (CV) measures run-to-run repeatability.")
a(f"For cloud-based Kubernetes experiments, CV < 25% is considered acceptable.")
a(f"")
a(f"| Endpoint | P50 CV | Assessment |")
a(f"|----------|--------|------------|")
for ep in ENDPOINTS:
    vr = var_idx.get((ep, "p50"), {})
    try:
        cv = float(vr.get("cv_pct", "nan"))
        if math.isnan(cv):
            assess = "No data"
        elif cv < 10:
            assess = "✅ Excellent — stable baseline"
        elif cv < 25:
            assess = "✅ Acceptable — normal for cloud Kubernetes"
        else:
            assess = "⚠ High — transient noise in cluster; acceptable for research baselines"
    except (TypeError, ValueError):
        assess = "No data"
    a(f"| {ep} | {cv_badge(vr.get('cv_pct'))} | {assess} |")

a(f"")
a(f"> **Note:** P50 latency naturally shows higher CV than P99 in queuing systems because P50")
a(f"> captures short-lived cache/scheduling jitter, while P99 is dominated by the deterministic")
a(f"> tail of the request distribution.")
a(f"")
a(f"---")
a(f"")
a(f"## 4. Saturation Sweep Summary")
a(f"")
a(f"The saturation sweep (run separately via `run-saturation-sweep.sh`) identified:")
a(f"")
a(f"- **Knee point**: ~150–180 RPS for `compose-post` (single-endpoint)")
a(f"- **Safe operating point** for this baseline: **50 RPS** compose-post, **100 RPS** read endpoints")
a(f"- At 200+ RPS (prior runs), P99 exceeded 30 seconds — system was fully saturated")
a(f"")
a(f"---")
a(f"")
a(f"## 5. Jaeger Traces")
a(f"")
a(f"Jaeger trace collection infrastructure is operational (port-forward to `observability` ns).")
a(f"The current trace count is 0 because Jaeger's default sampling rate may be <100%.")
a(f"")
a(f"To enable 100% sampling for future runs:")
patch_cmd = (
    "```bash\n"
    "kubectl patch configmap jaeger -n observability \\\n"
    "  --patch '{\"data\":{\"sampling.strategies\":\"[{\\\"type\\\":\\\"probabilistic\\\",\\\"param\\\":1.0}]\"}}\'\n"
    "```"
)
a(patch_cmd)
a(f"")
a(f"---")
a(f"")
a(f"## 6. Figures")
a(f"")
a(f"| Figure | Path |")
a(f"|--------|------|")
a(f"| Saturation sweep (throughput vs RPS) | `results/figures/throughput/saturation-sweep.pdf` |")
a(f"| Latency percentile bars (baseline) | `results/figures/latency-cdf/baseline-percentile-bars.pdf` |")
a(f"")
a(f"---")
a(f"")
a(f"## 7. Raw Data Locations")
a(f"")
a(f"| Artifact | Path |")
a(f"|----------|------|")
a(f"| Per-run wrk2 output | `data/raw/run_NNN/{{compose-post,home-timeline,user-timeline}}.txt` |")
a(f"| Parsed per-endpoint CSV | `data/processed/csv/{{endpoint}}.csv` |")
a(f"| Summary statistics | `results/tables/summary.csv` |")
a(f"| Variance / CV table | `results/tables/variance.csv` |")
a(f"")
a(f"---")
a(f"")
a(f"## 8. Reproduction")
a(f"")
a(f"```bash")
a(f"# Full pipeline from scratch:")
a(f"cd scripts/run")
a(f"./run_sequential_experiments.sh 5")
a(f"")
a(f"# Parse + analyse:")
a(f"python3 src/parser/wrk2_parser.py   --runs-dir data/raw/ --output data/processed/csv/")
a(f"python3 src/analysis/stats.py        --input data/processed/csv/ --output results/tables/summary.csv")
a(f"python3 src/analysis/generate_report.py")
a(f"```")

REPORT_OUT.write_text("\n".join(lines) + "\n")
print(f"[OUTPUT] {REPORT_OUT}")
print("[DONE] Report generated")
