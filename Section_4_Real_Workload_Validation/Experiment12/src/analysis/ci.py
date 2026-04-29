#!/usr/bin/env python3
"""
95% CI via bootstrap resampling (N=10,000) for Experiment 12.
Standalone module used by stats.py.

Usage:
  python3 ci.py --input data/processed/csv/ --output results/tables/variance.csv
"""

import csv
import argparse
import numpy as np
from pathlib import Path


PERCENTILE_COLS = ["p50", "p75", "p90", "p95", "p99", "p99_9", "p99_99"]
ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
N_BOOTSTRAP = 10_000
CI_LEVEL = 95
CV_THRESHOLD = 5.0


def bootstrap_ci(data, n_boot=N_BOOTSTRAP, ci=CI_LEVEL):
    """Compute 95% CI via bootstrap resampling of the median."""
    data = np.array([x for x in data if x is not None and not np.isnan(x)])
    if len(data) == 0:
        return float("nan"), float("nan"), float("nan")
    median_val = float(np.median(data))
    boot_medians = [np.median(np.random.choice(data, len(data), replace=True))
                    for _ in range(n_boot)]
    lo = float(np.percentile(boot_medians, (100 - ci) / 2))
    hi = float(np.percentile(boot_medians, 100 - (100 - ci) / 2))
    return median_val, lo, hi


def coefficient_of_variation(data):
    data = np.array([x for x in data if x is not None and not np.isnan(x)])
    if len(data) < 2 or np.mean(data) == 0:
        return float("nan")
    return 100.0 * np.std(data, ddof=1) / np.mean(data)


def analyze_variance(input_dir: Path, output_path: Path):
    """Compute CV and CI for all endpoints and flag high-variance runs."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    rows = []

    for endpoint in ENDPOINTS:
        csv_file = input_dir / f"{endpoint}.csv"
        if not csv_file.exists():
            print(f"[WARN] {csv_file} not found, skipping")
            continue

        data_rows = list(csv.DictReader(open(csv_file)))
        print(f"\nEndpoint: {endpoint} ({len(data_rows)} runs)")

        for col in PERCENTILE_COLS:
            values = []
            for r in data_rows:
                v = r.get(col)
                if v not in (None, "", "None"):
                    try:
                        values.append(float(v))
                    except ValueError:
                        pass

            cv = coefficient_of_variation(values)
            median_val, ci_lo, ci_hi = bootstrap_ci(values)
            flag = "⚠ HIGH CV" if (col == "p50" and cv > CV_THRESHOLD) else ""

            print(f"  {col:10s}: median={median_val:.3f}  CI=[{ci_lo:.3f},{ci_hi:.3f}]  CV={cv:.1f}%  {flag}")

            rows.append({
                "endpoint": endpoint,
                "metric": col,
                "n_runs": len(values),
                "median_ms": round(median_val, 3),
                "ci_lo_ms": round(ci_lo, 3),
                "ci_hi_ms": round(ci_hi, 3),
                "cv_pct": round(cv, 2),
                "flag": flag.strip(),
            })

    fieldnames = ["endpoint", "metric", "n_runs", "median_ms", "ci_lo_ms", "ci_hi_ms", "cv_pct", "flag"]
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n[OUTPUT] {output_path}")

    high_cv = [r for r in rows if r["flag"]]
    if high_cv:
        print(f"\n⚠  {len(high_cv)} metric(s) have CV > {CV_THRESHOLD}% on P50")
    else:
        print(f"\n✔  All P50 CV ≤ {CV_THRESHOLD}%")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="data/processed/csv/ directory")
    parser.add_argument("--output", default="results/tables/variance.csv")
    args = parser.parse_args()

    np.random.seed(42)
    analyze_variance(Path(args.input), Path(args.output))
    print("[DONE]")
