#!/usr/bin/env python3
"""
Statistical analysis for Experiment 12.
Computes median, 95% CI (bootstrap), and CV across 5 repetitions
per endpoint per percentile.

Outputs:
  results/tables/summary.csv   — median + 95% CI per endpoint per metric
  results/tables/variance.csv  — CV per endpoint per metric (flag if CV > 5%)

Usage:
  python3 stats.py --input data/processed/csv/ --output results/tables/summary.csv
"""

import csv
import argparse
import numpy as np
from pathlib import Path


PERCENTILE_COLS = ["p50", "p75", "p90", "p95", "p99", "p99_9", "p99_99"]
ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
N_BOOTSTRAP = 10_000
CI_LEVEL = 95
CV_THRESHOLD = 5.0   # Flag runs where CV > 5% on P50


def bootstrap_ci(data: list[float], n_boot: int = N_BOOTSTRAP, ci: int = CI_LEVEL) -> tuple[float, float]:
    """95% CI by bootstrap resampling."""
    data = np.array([x for x in data if x is not None])
    if len(data) == 0:
        return (float("nan"), float("nan"))
    boot_medians = [np.median(np.random.choice(data, len(data), replace=True))
                    for _ in range(n_boot)]
    lo = np.percentile(boot_medians, (100 - ci) / 2)
    hi = np.percentile(boot_medians, 100 - (100 - ci) / 2)
    return (lo, hi)


def coefficient_of_variation(data: list[float]) -> float:
    data = np.array([x for x in data if x is not None])
    if len(data) < 2 or np.mean(data) == 0:
        return float("nan")
    return 100.0 * np.std(data, ddof=1) / np.mean(data)


def load_csv(csv_path: Path) -> list[dict]:
    with open(csv_path) as f:
        return list(csv.DictReader(f))


def compute_stats(input_dir: Path, summary_out: Path, variance_out: Path):
    summary_rows = []
    variance_rows = []

    for endpoint in ENDPOINTS:
        csv_file = input_dir / f"{endpoint}.csv"
        if not csv_file.exists():
            print(f"[WARN] {csv_file} not found, skipping")
            continue

        rows = load_csv(csv_file)
        print(f"\nEndpoint: {endpoint}  ({len(rows)} run(s))")

        for col in PERCENTILE_COLS:
            values = []
            for row in rows:
                v = row.get(col)
                if v not in (None, "", "None"):
                    try:
                        values.append(float(v))
                    except ValueError:
                        pass

            if not values:
                print(f"  {col}: no data")
                continue

            median_val = float(np.median(values))
            ci_lo, ci_hi = bootstrap_ci(values)
            cv = coefficient_of_variation(values)
            flag = "⚠ HIGH CV" if (col == "p50" and cv > CV_THRESHOLD) else ""

            print(f"  {col:10s}: median={median_val:.3f}ms  "
                  f"95%CI=[{ci_lo:.3f}, {ci_hi:.3f}]  CV={cv:.1f}%  {flag}")

            summary_rows.append({
                "endpoint": endpoint,
                "metric": col,
                "n_runs": len(values),
                "median_ms": round(median_val, 3),
                "ci_lo_ms": round(ci_lo, 3),
                "ci_hi_ms": round(ci_hi, 3),
            })
            variance_rows.append({
                "endpoint": endpoint,
                "metric": col,
                "n_runs": len(values),
                "cv_pct": round(cv, 2),
                "flag": flag.strip(),
                "values": str([round(v, 3) for v in values]),
            })

        # Throughput
        tps = [float(r["throughput_rps"]) for r in rows if r.get("throughput_rps")]
        if tps:
            print(f"  {'throughput':10s}: median={np.median(tps):.1f} RPS")

    # Write outputs
    summary_out.parent.mkdir(parents=True, exist_ok=True)
    with open(summary_out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["endpoint","metric","n_runs","median_ms","ci_lo_ms","ci_hi_ms"])
        writer.writeheader()
        writer.writerows(summary_rows)
    print(f"\n[OUTPUT] {summary_out}")

    with open(variance_out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["endpoint","metric","n_runs","cv_pct","flag","values"])
        writer.writeheader()
        writer.writerows(variance_rows)
    print(f"[OUTPUT] {variance_out}")

    # Check for high-CV runs
    high_cv = [r for r in variance_rows if r["flag"]]
    if high_cv:
        print(f"\n⚠  {len(high_cv)} metric(s) have CV > {CV_THRESHOLD}% on P50 — consider repeating those runs")
    else:
        print(f"\n✔  All P50 CV < {CV_THRESHOLD}% — statistical quality OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="data/processed/csv/ directory")
    parser.add_argument("--output", default="results/tables/summary.csv", help="Summary CSV output")
    args = parser.parse_args()

    input_dir = Path(args.input)
    summary_out = Path(args.output)
    variance_out = summary_out.parent / "variance.csv"

    np.random.seed(42)   # reproducible bootstrap
    compute_stats(input_dir, summary_out, variance_out)
    print("\n[DONE] Statistics complete")
