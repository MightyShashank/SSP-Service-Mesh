#!/usr/bin/env python3
"""
Experiment 13 — Amplification analysis.
Computes per-endpoint latency amplification ratios relative to the
Experiment 12 baseline (summary.csv), for each victim case and noisy RPS level.

Usage:
  python3 amplification.py \
    --baseline ../../Experiment12/results/tables/summary.csv \
    --data data/processed/csv/ \
    --output results/tables/amplification.csv

Output CSV columns:
  case, mode, noisy_rps, endpoint, metric, baseline_ms, noisy_ms, amplification_x, goodput_drop_pct
"""

import argparse
import csv
import os
from pathlib import Path
from collections import defaultdict
import statistics


ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
METRICS   = ["p50", "p99", "p99_9", "p99_99"]


def load_baseline(baseline_csv: Path) -> dict:
    """Load Experiment 12 baseline medians. Returns {(endpoint, metric): value_ms}"""
    baseline = {}
    for row in csv.DictReader(open(baseline_csv)):
        ep  = row.get("endpoint", "")
        met = row.get("metric", "")
        val = row.get("median_ms", "")
        if ep and met and val:
            try:
                baseline[(ep, met)] = float(val)
            except ValueError:
                pass
    return baseline


def load_noisy_results(csv_dir: Path) -> dict:
    """
    Load all trial CSVs from data/processed/csv/<case>/<mode>/<noisy_rps>/<endpoint>.csv
    Returns {(case, mode, noisy_rps, endpoint, metric): [values...]}
    """
    results = defaultdict(list)
    for case_dir in sorted(csv_dir.glob("case-*")):
        case = case_dir.name.replace("case-", "")
        for mode_dir in sorted(case_dir.iterdir()):
            mode = mode_dir.name
            for rps_dir in sorted(mode_dir.iterdir()):
                try:
                    noisy_rps = int(rps_dir.name.replace("rps", "").replace("_", ""))
                except ValueError:
                    noisy_rps = 0
                for ep in ENDPOINTS:
                    f = rps_dir / f"{ep}.csv"
                    if not f.exists():
                        continue
                    for row in csv.DictReader(open(f)):
                        for met in METRICS:
                            val = row.get(met, "")
                            if val and val not in ("None", "nan", ""):
                                try:
                                    results[(case, mode, noisy_rps, ep, met)].append(float(val))
                                except ValueError:
                                    pass
    return dict(results)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, help="Experiment 12 summary.csv")
    parser.add_argument("--data",     required=True, help="data/processed/csv/ directory")
    parser.add_argument("--output",   required=True, help="Output CSV path")
    args = parser.parse_args()

    baseline = load_baseline(Path(args.baseline))
    if not baseline:
        print("[ERROR] Could not load baseline — check path")
        return

    noisy   = load_noisy_results(Path(args.data))
    rows    = []

    for (case, mode, noisy_rps, ep, met), vals in sorted(noisy.items()):
        b_val = baseline.get((ep, met))
        if b_val is None or b_val == 0:
            continue
        median_noisy = statistics.median(vals)
        amp = median_noisy / b_val
        rows.append({
            "case":          case,
            "mode":          mode,
            "noisy_rps":     noisy_rps,
            "endpoint":      ep,
            "metric":        met,
            "baseline_ms":   round(b_val, 2),
            "noisy_ms":      round(median_noisy, 2),
            "amplification_x": round(amp, 3),
        })

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "case", "mode", "noisy_rps", "endpoint", "metric",
            "baseline_ms", "noisy_ms", "amplification_x"
        ])
        writer.writeheader()
        writer.writerows(rows)

    print(f"[OUTPUT] {args.output}  ({len(rows)} rows)")

    # Console summary
    print("\n── Amplification Summary (P99.99, sustained-ramp) ──")
    for row in rows:
        if row["metric"] == "p99_99" and row["mode"] == "sustained-ramp":
            print(f"  Case {row['case']} | {row['endpoint']:15s} | "
                  f"{row['noisy_rps']:4d} RPS noisy → "
                  f"{row['amplification_x']:.2f}×  "
                  f"({row['baseline_ms']} → {row['noisy_ms']} ms)")


if __name__ == "__main__":
    main()
