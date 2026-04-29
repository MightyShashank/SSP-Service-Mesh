#!/usr/bin/env python3
"""
Plot C: ztunnel CPU over time.
Parses the timestamped TSV produced by capture-ztunnel-cpu-top.sh
and plots CPU millicores over the experiment measurement window.

If no real data exists yet (first runs before the new poller was integrated),
renders a clear "no data" placeholder with instructions.

Usage:
  python3 cpu_plots.py --runs-dir data/raw/ --output results/figures/ztunnel-cpu/
  python3 cpu_plots.py --data data/raw/run_001/ztunnel-top.txt --output results/figures/ztunnel-cpu/
"""

import argparse
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from pathlib import Path
from datetime import datetime
from collections import defaultdict


COLORS = ["#e74c3c", "#3498db", "#2ecc71", "#9b59b6", "#f39c12"]


def parse_ztunnel_top(filepath: Path):
    """
    Parse capture-ztunnel-cpu-top.sh TSV output.
    Returns {pod_name: [(datetime, cpu_millicores), ...]}
    """
    series = defaultdict(list)
    if not filepath.exists():
        return series
    for line in filepath.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = line.strip().split("\t")
        if len(parts) < 3:
            continue
        try:
            ts  = datetime.fromisoformat(parts[0])
            pod = parts[1]
            cpu = int(parts[2])
            series[pod].append((ts, cpu))
        except (ValueError, IndexError):
            continue
    return dict(series)


def plot_no_data(output_dir: Path, run_label: str = ""):
    """Render a placeholder figure with instructions when no data is available."""
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.text(0.5, 0.6, "ztunnel CPU data not yet collected",
            ha="center", va="center", fontsize=16, color="#7f8c8d",
            transform=ax.transAxes)
    ax.text(0.5, 0.42,
            "Re-run the experiment — capture-ztunnel-cpu-top.sh is now\n"
            "integrated into run-experiment.sh and will collect data automatically.",
            ha="center", va="center", fontsize=11, color="#95a5a6",
            transform=ax.transAxes)
    ax.text(0.5, 0.25,
            "Output will be saved to: data/raw/run_NNN/ztunnel-top.txt",
            ha="center", va="center", fontsize=10, color="#bdc3c7",
            transform=ax.transAxes)
    ax.set_axis_off()
    ax.set_title(f"Experiment 12: ztunnel CPU Utilization Over Time{' — ' + run_label if run_label else ''}\n"
                 "(DeathStarBench Social Network · Istio Ambient Mesh)",
                 fontsize=12, fontweight="bold")
    fig.tight_layout()
    for ext in ("pdf", "png"):
        out = output_dir / f"ztunnel-cpu.{ext}"
        fig.savefig(out, dpi=150, bbox_inches="tight")
        print(f"[OUTPUT] {out} (placeholder — no data)")
    plt.close(fig)


def plot_cpu_series(all_series: dict, output_dir: Path, title_suffix: str = ""):
    """Plot CPU millicores over time for one or more runs."""
    output_dir.mkdir(parents=True, exist_ok=True)

    if not all_series:
        plot_no_data(output_dir)
        return

    fig, ax = plt.subplots(figsize=(12, 5))
    color_idx = 0
    any_data = False

    for label, series in sorted(all_series.items()):
        if not series:
            continue
        times = [s[0] for s in series]
        cpus  = [s[1] for s in series]
        # Normalise timestamps to seconds-since-start
        t0 = times[0]
        elapsed = [(t - t0).total_seconds() for t in times]
        ax.plot(elapsed, cpus, "o-",
                color=COLORS[color_idx % len(COLORS)],
                linewidth=2, markersize=4, label=label, alpha=0.85)
        color_idx += 1
        any_data = True

    if not any_data:
        plt.close(fig)
        plot_no_data(output_dir)
        return

    ax.set_xlabel("Time since measurement start (s)", fontsize=11)
    ax.set_ylabel("CPU (millicores)", fontsize=11)
    ax.set_title(f"Experiment 12: ztunnel CPU Utilization Over Time{title_suffix}\n"
                 "(DeathStarBench Social Network · Istio Ambient Mesh)",
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=9)
    ax.grid(alpha=0.3, linestyle="--")
    ax.set_ylim(bottom=0)

    # Reference lines at 250m, 500m, 1000m
    for ref, lbl in [(250, "250m (¼ core)"), (500, "500m (½ core)"), (1000, "1 core")]:
        ax.axhline(y=ref, color="#bdc3c7", linestyle=":", linewidth=1, alpha=0.7)
        ax.text(ax.get_xlim()[1] * 0.98, ref + 10, lbl,
                ha="right", fontsize=8, color="#7f8c8d")

    fig.tight_layout()
    for ext in ("pdf", "png"):
        out = output_dir / f"ztunnel-cpu.{ext}"
        fig.savefig(out, dpi=150, bbox_inches="tight")
        print(f"[OUTPUT] {out}")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description="Plot ztunnel CPU over time")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--data",     help="Single ztunnel-top.txt file")
    group.add_argument("--runs-dir", help="data/raw/ directory — aggregates all run_*/ztunnel-top.txt")
    parser.add_argument("--output", required=True, help="Output directory for figures")
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.data:
        fp = Path(args.data)
        series = parse_ztunnel_top(fp)
        if series:
            all_series = {f"{pod}": v for pod, v in series.items()}
            plot_cpu_series(all_series, output_dir)
        else:
            print(f"[WARN] No data in {fp}")
            plot_no_data(output_dir)

    else:
        runs_dir = Path(args.runs_dir)
        run_dirs = sorted(runs_dir.glob("run_*"))
        if not run_dirs:
            print(f"[ERROR] No run_* dirs in {runs_dir}")
            return

        # Collect per-run averages for a summary plot (one line per run)
        all_series = {}
        any_found = False
        for run_dir in run_dirs:
            fp = run_dir / "ztunnel-top.txt"
            series = parse_ztunnel_top(fp)
            if series:
                any_found = True
                # Merge all ztunnel pods in this run into one series (sum CPUs per timestamp)
                merged = defaultdict(int)
                for pod_series in series.values():
                    for ts, cpu in pod_series:
                        merged[ts] += cpu
                all_series[run_dir.name] = [(ts, cpu) for ts, cpu in sorted(merged.items())]

        if any_found:
            plot_cpu_series(all_series, output_dir, title_suffix=" — all runs")
        else:
            print("[WARN] No ztunnel-top.txt data found in any run — generating placeholder")
            plot_no_data(output_dir)

    print("[DONE]")


if __name__ == "__main__":
    main()
