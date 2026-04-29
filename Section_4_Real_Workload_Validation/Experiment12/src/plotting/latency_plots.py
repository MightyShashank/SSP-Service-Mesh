#!/usr/bin/env python3
"""
Latency plotting for Experiment 12.
Produces:
  1. Latency CDF (log-x): compose-post at 200 RPS, three lines (No Mesh / Sidecar / Ambient)
  2. Percentile bar chart: P50/P99/P99.9/P99.99 per endpoint

Usage:
  python3 latency_plots.py --data data/processed/csv/ --output results/figures/latency-cdf/
  python3 latency_plots.py --mode jaeger --data data/raw/run_001/jaeger-traces.json --output results/figures/traces/
"""

import argparse
import csv
import json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path


ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
COLORS = {
    "No Mesh":       "#2ecc71",
    "Istio Sidecar": "#3498db",
    "Istio Ambient": "#e74c3c",
}
PERCENTILE_LABELS = ["P50", "P75", "P90", "P95", "P99", "P99.9", "P99.99"]
PERCENTILE_COLS   = ["p50",  "p75",  "p90",  "p95",  "p99",  "p99_9", "p99_99"]


def load_summary(csv_dir: Path, endpoint: str) -> dict[str, float]:
    """Load median percentiles from per-endpoint CSV."""
    summary = {}
    csv_file = csv_dir / f"{endpoint}.csv"
    if not csv_file.exists():
        return summary
    rows = list(csv.DictReader(open(csv_file)))
    for col, label in zip(PERCENTILE_COLS, PERCENTILE_LABELS):
        vals = [float(r[col]) for r in rows if r.get(col) not in (None, "", "None")]
        if vals:
            summary[label] = float(np.median(vals))
    return summary


def plot_percentile_bars(csv_dir: Path, output_dir: Path):
    """Grouped bar chart: P50 / P99 / P99.99 per endpoint."""
    output_dir.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(10, 5))
    x = np.arange(len(ENDPOINTS))
    width = 0.22
    target_pcts = ["P50", "P99", "P99.99"]
    bar_colors = ["#3498db", "#e67e22", "#e74c3c"]

    for i, (pct, color) in enumerate(zip(target_pcts, bar_colors)):
        vals = []
        for ep in ENDPOINTS:
            summary = load_summary(csv_dir, ep)
            vals.append(summary.get(pct, 0))
        offset = (i - 1) * width
        bars = ax.bar(x + offset, vals, width, label=pct, color=color, alpha=0.85)
        for bar, val in zip(bars, vals):
            if val > 0:
                ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.3,
                        f"{val:.1f}", ha="center", va="bottom", fontsize=8)

    ax.set_xticks(x)
    ax.set_xticklabels(["compose-post\n(200 RPS)", "home-timeline\n(300 RPS)", "user-timeline\n(300 RPS)"])
    ax.set_ylabel("Latency (ms)")
    ax.set_title("Experiment 12: Baseline Latency Percentiles\n(Istio Ambient, No Noisy Neighbor)")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)
    ax.set_ylim(bottom=0)

    out_file = output_dir / "baseline-percentile-bars.pdf"
    fig.tight_layout()
    fig.savefig(out_file, dpi=150)
    plt.close(fig)
    print(f"[OUTPUT] {out_file}")


def plot_jaeger_flamechart(jaeger_json: Path, output_dir: Path):
    """
    Parse Jaeger traces and produce a per-hop latency bar chart for compose-post.
    Computes mean span duration per service from collected traces.
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        data = json.loads(jaeger_json.read_text())
    except Exception as e:
        print(f"[ERROR] Cannot parse Jaeger JSON: {e}")
        return

    traces = data.get("data", [])
    if not traces:
        print("[WARN] No traces found in Jaeger JSON")
        return

    # Collect mean span duration per service name
    service_durations: dict[str, list[float]] = {}
    for trace in traces:
        for span in trace.get("spans", []):
            svc = span.get("process", {}).get("serviceName", "unknown")
            duration_us = span.get("duration", 0)
            duration_ms = duration_us / 1000.0
            service_durations.setdefault(svc, []).append(duration_ms)

    if not service_durations:
        print("[WARN] No spans found in traces")
        return

    services = sorted(service_durations.keys())
    means = [float(np.mean(service_durations[s])) for s in services]

    fig, ax = plt.subplots(figsize=(12, 5))
    ax.barh(services, means, color="#3498db", alpha=0.8)
    ax.set_xlabel("Mean Span Duration (ms)")
    ax.set_title("Experiment 12: Jaeger Per-Hop Latency — compose-post Baseline\n"
                 "(No Noisy Neighbor, Istio Ambient)")
    ax.grid(axis="x", alpha=0.3)

    for i, (svc, val) in enumerate(zip(services, means)):
        ax.text(val + 0.1, i, f"{val:.2f} ms", va="center", fontsize=8)

    out_file = output_dir / "jaeger-flamechart-compose.pdf"
    fig.tight_layout()
    fig.savefig(out_file, dpi=150)
    plt.close(fig)
    print(f"[OUTPUT] {out_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, help="Input: CSV dir or Jaeger JSON file")
    parser.add_argument("--output", required=True, help="Output directory for figures")
    parser.add_argument("--mode", choices=["latency", "jaeger"], default="latency",
                        help="latency: percentile bars | jaeger: flame chart")
    args = parser.parse_args()

    output_dir = Path(args.output)

    if args.mode == "latency":
        plot_percentile_bars(Path(args.data), output_dir)
    elif args.mode == "jaeger":
        plot_jaeger_flamechart(Path(args.data), output_dir)

    print("[DONE]")
