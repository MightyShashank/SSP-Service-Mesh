#!/usr/bin/env python3
"""
Combined report figure generation for Experiment 12.
Generates all paper figures in one run.

Usage:
  python3 report_plots.py --data-dir data/ --output-dir results/figures/
"""

import argparse
from pathlib import Path

# Import sibling plotting modules
import sys
sys.path.insert(0, str(Path(__file__).parent))

from latency_plots import plot_percentile_bars, plot_jaeger_flamechart
from saturation_plots import plot_saturation_sweep
from cpu_plots import plot_cpu


def generate_all_figures(data_dir: Path, output_dir: Path, run_id: str = "run_001"):
    """Generate all paper figures for Experiment 12."""

    print("=" * 60)
    print("  Experiment 12 — Report Figure Generation")
    print("=" * 60)

    csv_dir = data_dir / "processed" / "csv"
    raw_dir = data_dir / "raw"

    # Figure 1: Percentile bar chart
    print("\n--- Figure 1: Percentile Bars ---")
    if csv_dir.exists():
        plot_percentile_bars(csv_dir, output_dir / "tail-percentiles")
    else:
        print("[SKIP] No processed CSVs found")

    # Figure 2: Saturation sweep
    print("\n--- Figure 2: Saturation Sweep ---")
    sweep_dir = raw_dir / "saturation-sweep"
    if sweep_dir.exists():
        plot_saturation_sweep(sweep_dir, output_dir / "throughput")
    else:
        print("[SKIP] No saturation sweep data found")

    # Figure 3: Jaeger flame chart
    print("\n--- Figure 3: Jaeger Flame Chart ---")
    jaeger_file = raw_dir / run_id / "jaeger-traces.json"
    if jaeger_file.exists():
        plot_jaeger_flamechart(jaeger_file, output_dir / "traces")
    else:
        print(f"[SKIP] No Jaeger traces found at {jaeger_file}")

    # Figure 4: ztunnel CPU
    print("\n--- Figure 4: ztunnel CPU ---")
    cpu_file = raw_dir / run_id / "ztunnel-cpu.txt"
    if cpu_file.exists():
        plot_cpu(cpu_file, output_dir / "ztunnel-cpu")
    else:
        print(f"[SKIP] No CPU data found at {cpu_file}")

    print("\n" + "=" * 60)
    print("  All figures generated → " + str(output_dir))
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="data", help="Root data directory")
    parser.add_argument("--output-dir", default="results/figures", help="Output directory")
    parser.add_argument("--run-id", default="run_001", help="Run ID for trace/CPU data")
    args = parser.parse_args()

    generate_all_figures(Path(args.data_dir), Path(args.output_dir), args.run_id)
