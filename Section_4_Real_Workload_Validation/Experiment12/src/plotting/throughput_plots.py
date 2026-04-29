#!/usr/bin/env python3
"""
Plot B: Throughput vs Offered Load (saturation sweep).
Shows achieved RPS vs target RPS with ideal-line and saturation zone.

Usage:
  python3 throughput_plots.py --data data/raw/saturation-sweep/ --output results/figures/throughput/
"""

import re
import argparse
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from pathlib import Path


def parse_sweep(sweep_dir: Path):
    """Extract (target_rps, achieved_rps, p99_ms) from all sweep files."""
    points = []
    for f in sorted(sweep_dir.glob("compose-post-*rps.txt"),
                    key=lambda x: int(re.search(r"(\d+)rps", x.name).group(1))):
        target = int(re.search(r"(\d+)rps", f.name).group(1))
        achieved, p99_ms = None, None
        for line in f.read_text().splitlines():
            if "Requests/sec:" in line:
                achieved = float(line.strip().split()[-1])
            if "99.000%" in line:
                parts = line.strip().split()
                v = parts[1]
                if v.endswith("ms"):
                    p99_ms = float(v[:-2])
                elif v.endswith("us"):
                    p99_ms = float(v[:-2]) / 1000
                elif v.endswith("m"):
                    p99_ms = float(v[:-1]) * 60_000
                elif v.endswith("s"):
                    p99_ms = float(v[:-1]) * 1000
        if achieved is not None:
            points.append((target, achieved, p99_ms or 0))
    return points


def plot_throughput_vs_load(sweep_dir: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    points = parse_sweep(sweep_dir)
    if not points:
        print("[ERROR] No sweep data found")
        return

    targets  = [p[0] for p in points]
    achieved = [p[1] for p in points]
    p99s     = [p[2] / 1000 for p in points]   # convert to seconds

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 8), sharex=True,
                                    gridspec_kw={"height_ratios": [1, 1.5]})

    # ── Top panel: Throughput vs Offered Load ────────────────────────────────
    max_target = max(targets)
    ax1.plot(targets, targets, "k--", linewidth=1.5, alpha=0.4, label="Ideal (achieved = offered)")
    ax1.plot(targets, achieved, "o-", color="#2980b9", linewidth=2.5,
             markersize=7, label="Achieved throughput")

    # Saturation region: where achieved < 95% of offered
    knee = next((t for t, a in zip(targets, achieved) if a < 0.95 * t), None)
    if knee:
        ax1.axvspan(knee, max_target + 20, alpha=0.08, color="#e74c3c", label="Saturated region")
        ax1.axvline(x=knee, color="#e74c3c", linestyle=":", linewidth=1.5)

    # Op point
    ax1.axvline(x=50, color="#27ae60", linestyle="--", linewidth=2, label="Baseline op. point (50 RPS)")
    ax1.set_ylabel("Throughput (RPS)", fontsize=11)
    ax1.set_title("Experiment 12: Throughput vs Offered Load\n"
                  "(DeathStarBench compose-post · Istio Ambient Mesh)", fontsize=12, fontweight="bold")
    ax1.legend(fontsize=9, loc="upper left")
    ax1.grid(alpha=0.3, linestyle="--")
    ax1.set_ylim(bottom=0)

    # ── Bottom panel: P99 Latency vs Offered Load ────────────────────────────
    ax2.plot(targets, p99s, "s-", color="#e74c3c", linewidth=2.5,
             markersize=7, label="P99 latency")
    ax2.axhline(y=1.0, color="#e67e22", linestyle="--", linewidth=1.5,
                label="1 s SLO boundary")
    if knee:
        ax2.axvspan(knee, max_target + 20, alpha=0.08, color="#e74c3c")
        ax2.axvline(x=knee, color="#e74c3c", linestyle=":", linewidth=1.5,
                    label=f"Knee ≈ {knee} RPS")
    ax2.axvline(x=50, color="#27ae60", linestyle="--", linewidth=2,
                label="Baseline op. point (50 RPS)")

    ax2.set_xlabel("Offered Load (RPS)", fontsize=11)
    ax2.set_ylabel("P99 Latency (s)", fontsize=11)
    ax2.set_title("P99 Latency vs Offered Load", fontsize=11)
    ax2.legend(fontsize=9, loc="upper left")
    ax2.grid(alpha=0.3, linestyle="--")
    ax2.set_ylim(bottom=0)
    ax2.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.1f s"))
    ax2.set_xlim(left=0, right=max_target + 30)

    fig.tight_layout()
    for ext in ("pdf", "png"):
        out = output_dir / f"throughput-vs-load.{ext}"
        fig.savefig(out, dpi=150, bbox_inches="tight")
        print(f"[OUTPUT] {out}")
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, help="data/raw/saturation-sweep/ directory")
    parser.add_argument("--output", required=True, help="Output directory for figures")
    args = parser.parse_args()
    plot_throughput_vs_load(Path(args.data), Path(args.output))
    print("[DONE]")
