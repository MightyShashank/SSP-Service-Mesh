#!/usr/bin/env python3
"""
Plot D: Endpoint Tail Latency CDF.
Extracts the HdrHistogram detailed percentile spectrum from each wrk2 output
file and plots the CDF (latency on X-axis, percentile on Y-axis) for all
three endpoints on a single figure, using a log-scale Y-axis to emphasise
the tail.

Usage:
  python3 cdf_plots.py --runs-dir data/raw/ --output results/figures/latency-cdf/
"""

import re
import argparse
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from pathlib import Path


ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
COLORS = {
    "compose-post":  "#e74c3c",
    "home-timeline": "#3498db",
    "user-timeline": "#2ecc71",
}
LABELS = {
    "compose-post":  "compose-post (write, 50 RPS)",
    "home-timeline": "home-timeline (read, 100 RPS)",
    "user-timeline": "user-timeline (read, 100 RPS)",
}


def parse_hdr_spectrum(filepath: Path):
    """
    Extract (value_ms, percentile) pairs from the HdrHistogram
    'Detailed Percentile spectrum' section of a wrk2 output file.
    """
    points = []
    in_spectrum = False
    try:
        for line in filepath.read_text().splitlines():
            if "Detailed Percentile spectrum" in line:
                in_spectrum = True
                continue
            if in_spectrum:
                # Stop at summary lines starting with #
                if line.strip().startswith("#") or line.strip().startswith("--"):
                    break
                # Data lines: "   value   percentile   count   1/(1-pct)"
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        val_ms = float(parts[0])        # wrk2 HdrHistogram in ms
                        pct    = float(parts[1])        # 0.0 – 1.0
                        points.append((val_ms, pct))
                    except ValueError:
                        pass
    except FileNotFoundError:
        pass
    return points


def aggregate_spectra(run_dirs, endpoint):
    """
    Combine HdrHistogram spectra from multiple runs for one endpoint.
    Returns (latency_ms, percentile) pairs sorted by percentile.
    """
    all_points = []
    for run_dir in run_dirs:
        pts = parse_hdr_spectrum(run_dir / f"{endpoint}.txt")
        all_points.extend(pts)
    if not all_points:
        return [], []
    # Sort by percentile, deduplicate by taking median latency per pct bucket
    all_points.sort(key=lambda x: x[1])
    # Bin into 200 equal-spaced percentile buckets between 0 and 0.9999
    pct_bins = np.linspace(0.0, 0.9999, 200)
    lats, pcts = [], []
    for pct in pct_bins:
        # find nearest actual point
        nearest = min(all_points, key=lambda x: abs(x[1] - pct))
        lats.append(nearest[0])
        pcts.append(nearest[1])
    return lats, pcts


def plot_cdf(runs_dir: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)

    run_dirs = sorted(runs_dir.glob("run_*"))
    if not run_dirs:
        print(f"[ERROR] No run_* directories found in {runs_dir}")
        return

    print(f"Using {len(run_dirs)} runs: {[d.name for d in run_dirs]}")

    fig, (ax_lin, ax_log) = plt.subplots(1, 2, figsize=(14, 6))

    for endpoint in ENDPOINTS:
        lats, pcts = aggregate_spectra(run_dirs, endpoint)
        if not lats:
            print(f"  [SKIP] {endpoint}: no HdrHistogram data")
            continue

        color = COLORS[endpoint]
        label = LABELS[endpoint]
        lat_s = [l / 1000.0 for l in lats]   # ms → s

        # Linear Y panel
        ax_lin.plot(lat_s, pcts, "-", color=color, linewidth=2, label=label)
        # Log Y panel (tail emphasis)
        ax_log.plot(lat_s, pcts, "-", color=color, linewidth=2, label=label)
        print(f"  [OK] {endpoint}: {len(lats)} spectrum points")

    # ── Linear panel ────────────────────────────────────────────────────────
    for ax in (ax_lin, ax_log):
        ax.axhline(y=0.99,  color="#e67e22", linestyle="--", linewidth=1,
                   alpha=0.7, label="P99")
        ax.axhline(y=0.999, color="#e74c3c", linestyle=":",  linewidth=1,
                   alpha=0.7, label="P99.9")
        ax.set_xlabel("Latency (s)", fontsize=11)
        ax.grid(alpha=0.3, linestyle="--")
        ax.set_xlim(left=0)

    ax_lin.set_ylabel("Cumulative Percentile", fontsize=11)
    ax_lin.set_ylim(0, 1.01)
    ax_lin.yaxis.set_major_formatter(ticker.PercentFormatter(xmax=1.0))
    ax_lin.set_title("Tail Latency CDF (linear scale)", fontsize=11, fontweight="bold")
    ax_lin.legend(fontsize=9)

    # ── Log Y panel ─────────────────────────────────────────────────────────
    # Transform: plot (1 - pct) on log scale so tail is stretched
    fig2, ax_tail = plt.subplots(figsize=(9, 6))
    for endpoint in ENDPOINTS:
        lats, pcts = aggregate_spectra(run_dirs, endpoint)
        if not lats:
            continue
        color  = COLORS[endpoint]
        label  = LABELS[endpoint]
        lat_s  = [l / 1000.0 for l in lats]
        # (1 - pct) for complementary CDF; clip to avoid log(0)
        ccdf = [max(1 - p, 1e-6) for p in pcts]
        ax_tail.semilogy(lat_s, ccdf, "-", color=color, linewidth=2.5, label=label)

    ax_tail.set_xlabel("Latency (s)", fontsize=11)
    ax_tail.set_ylabel("P(response time > x)  [log scale]", fontsize=11)
    ax_tail.set_title("Experiment 12: Complementary CDF — Tail Latency\n"
                      "(DeathStarBench Social Network · Istio Ambient Mesh · 5 runs)", fontsize=12, fontweight="bold")
    ax_tail.grid(alpha=0.3, linestyle="--", which="both")
    ax_tail.legend(fontsize=10)
    ax_tail.set_xlim(left=0)
    ax_tail.axhline(y=0.01,  color="#e67e22", linestyle="--", linewidth=1, alpha=0.7, label="P99")
    ax_tail.axhline(y=0.001, color="#e74c3c", linestyle=":",  linewidth=1, alpha=0.7, label="P99.9")
    ax_tail.set_ylim(bottom=1e-5, top=1.0)
    fig2.tight_layout()
    for ext in ("pdf", "png"):
        out = output_dir / f"tail-cdf.{ext}"
        fig2.savefig(out, dpi=150, bbox_inches="tight")
        print(f"[OUTPUT] {out}")
    plt.close(fig2)

    # Also save the linear CDF
    ax_log.set_title("Tail Latency CDF (log-tail scale)", fontsize=11, fontweight="bold")
    ax_log.set_yscale("log")
    ax_log.set_ylim(bottom=1e-2, top=1.0)
    ax_log.set_ylabel("Cumulative Percentile (log)", fontsize=11)
    ax_log.legend(fontsize=9)
    fig.suptitle("Experiment 12: Endpoint Tail Latency CDF\n"
                 "(DeathStarBench Social Network · Istio Ambient Mesh · 5 runs)",
                 fontsize=13, fontweight="bold")
    fig.tight_layout()
    for ext in ("pdf", "png"):
        out = output_dir / f"latency-cdf.{ext}"
        fig.savefig(out, dpi=150, bbox_inches="tight")
        print(f"[OUTPUT] {out}")
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs-dir", required=True, help="data/raw/ directory containing run_* dirs")
    parser.add_argument("--output",   required=True, help="Output directory for figures")
    args = parser.parse_args()
    plot_cdf(Path(args.runs_dir), Path(args.output))
    print("[DONE]")
