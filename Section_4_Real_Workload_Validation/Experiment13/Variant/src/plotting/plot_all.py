#!/usr/bin/env python3
"""
Experiment 13 Plots — all five figures from the paper spec.

Figure 1 (hero):      P99.99 of compose-post vs noisy RPS — sustained ramp, Case A
Figure 2 (ordering):  P99.99 amplification bar chart for Cases A, B, C at 700 RPS
Figure 3 (modes):     P99.99 side-by-side for sustained/burst/churn at matched mean 200 RPS
Figure 4 (cpu+queue): ztunnel CPU over time vs noisy RPS (from ztunnel-top.txt)
Figure 5 (baseline):  Per-endpoint latency bars with vs without noisy (overlay on Exp12)

Usage:
  python3 plot_all.py --data results/tables/amplification.csv \
                      --ztunnel-dir data/raw/ \
                      --baseline ../../Experiment12/results/tables/summary.csv \
                      --output results/figures/
"""

import argparse
import csv
import re
from pathlib import Path
from collections import defaultdict
from datetime import datetime

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ── Color palette ─────────────────────────────────────────────────────────────
CASE_COLORS = {"A": "#e74c3c", "B": "#3498db", "C": "#2ecc71"}
MODE_COLORS  = {
    "sustained-ramp": "#e74c3c",
    "burst":          "#9b59b6",
    "churn":          "#f39c12",
}
ENDPOINT_COLORS = {
    "compose-post":  "#e74c3c",
    "home-timeline": "#3498db",
    "user-timeline": "#2ecc71",
}


# ── Data loaders ──────────────────────────────────────────────────────────────

def load_amplification(csv_path: Path):
    rows = []
    if not csv_path.exists():
        return rows
    for row in csv.DictReader(open(csv_path)):
        try:
            row["noisy_rps"]       = int(row["noisy_rps"])
            row["amplification_x"] = float(row["amplification_x"])
            row["baseline_ms"]     = float(row["baseline_ms"])
            row["noisy_ms"]        = float(row["noisy_ms"])
            rows.append(row)
        except (ValueError, KeyError):
            pass
    return rows


def load_baseline(csv_path: Path):
    b = {}
    if not csv_path.exists():
        return b
    for row in csv.DictReader(open(csv_path)):
        b[(row.get("endpoint",""), row.get("metric",""))] = float(row.get("median_ms", 0) or 0)
    return b


def load_ztunnel_series(ztunnel_dir: Path, case: str, mode: str):
    """Aggregate all ztunnel-top.txt across trials for a given case+mode."""
    series = defaultdict(list)   # {elapsed_s: [cpu_m values]}
    pattern = ztunnel_dir / f"case-{case}" / mode
    for trial_dir in sorted(pattern.glob("trial_*")):
        fp = trial_dir / "ztunnel-top.txt"
        if not fp.exists():
            continue
        t0 = None
        for line in fp.read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            parts = line.strip().split("\t")
            if len(parts) < 3:
                continue
            try:
                ts  = datetime.fromisoformat(parts[0])
                cpu = int(parts[2])
                if t0 is None:
                    t0 = ts
                elapsed = round((ts - t0).total_seconds())
                series[elapsed].append(cpu)
            except (ValueError, IndexError):
                pass
    if not series:
        return [], []
    times = sorted(series.keys())
    cpus  = [np.median(series[t]) for t in times]
    return times, cpus


# ── Figure 1: Hero Figure ─────────────────────────────────────────────────────

def plot_hero(rows, output_dir: Path):
    """P99.99 amplification of compose-post vs noisy RPS, Case A, sustained-ramp."""
    data = [(r["noisy_rps"], r["amplification_x"])
            for r in rows
            if r["case"] == "A" and r["mode"] == "sustained-ramp"
            and r["endpoint"] == "compose-post" and r["metric"] == "p99_99"]
    data.sort()
    if not data:
        _placeholder(output_dir / "hero-p9999-vs-noisy-rps.png",
                     "Hero Figure (Fig 1)\nNo data yet — run Case A sustained-ramp trials")
        return

    xs, ys = zip(*data)
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(xs, ys, "o-", color="#e74c3c", linewidth=2.5, markersize=8, label="Ambient (stock)")
    ax.axhline(y=1.0, color="#27ae60", linestyle="--", linewidth=1.5, label="Baseline (1×)")
    ax.axhspan(1.0, max(ys) * 1.05, alpha=0.05, color="#e74c3c")

    ax.set_xlabel("Noisy Neighbor Load (RPS)", fontsize=12)
    ax.set_ylabel("P99.99 Amplification (×baseline)", fontsize=12)
    ax.set_title("Experiment 13 — Hero Figure\n"
                 "P99.99 Latency Amplification of compose-post vs Noisy Load\n"
                 "(Case A: social-graph victim · Sustained Ramp · Istio Ambient Mesh)",
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=10)
    ax.grid(alpha=0.3, linestyle="--")
    ax.set_ylim(bottom=0)
    fig.tight_layout()
    _save(fig, output_dir / "hero-p9999-vs-noisy-rps")


# ── Figure 2: Victim Ordering ─────────────────────────────────────────────────

def plot_victim_ordering(rows, output_dir: Path, noisy_rps: int = 700):
    """P99.99 amplification bar chart for Cases A, B, C at fixed noisy_rps."""
    endpoints = ["compose-post", "home-timeline", "user-timeline"]
    cases     = ["A", "B", "C"]
    labels    = {"A": "Case A\n(social-graph)", "B": "Case B\n(user-service)", "C": "Case C\n(media-service)"}

    fig, ax = plt.subplots(figsize=(11, 6))
    x      = np.arange(len(cases))
    width  = 0.25

    for i, ep in enumerate(endpoints):
        amps = []
        for case in cases:
            vals = [r["amplification_x"] for r in rows
                    if r["case"] == case and r["mode"] == "sustained-ramp"
                    and r["noisy_rps"] == noisy_rps
                    and r["endpoint"] == ep and r["metric"] == "p99_99"]
            amps.append(np.median(vals) if vals else 0)
        bars = ax.bar(x + (i - 1) * width, amps, width,
                      label=ep, color=ENDPOINT_COLORS[ep], alpha=0.85)
        for bar, v in zip(bars, amps):
            if v > 0:
                ax.text(bar.get_x() + bar.get_width() / 2,
                        bar.get_height() + 0.05, f"{v:.1f}×",
                        ha="center", va="bottom", fontsize=8)

    ax.axhline(y=1.0, color="#27ae60", linestyle="--", linewidth=1.5, label="Baseline (1×)")
    ax.set_xticks(x)
    ax.set_xticklabels([labels[c] for c in cases])
    ax.set_ylabel("P99.99 Amplification (×baseline)", fontsize=11)
    ax.set_title(f"Experiment 13 — Victim Ordering\n"
                 f"P99.99 Amplification per Case at {noisy_rps} RPS Noisy Load",
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=9)
    ax.grid(axis="y", alpha=0.3, linestyle="--")
    ax.set_ylim(bottom=0)
    fig.tight_layout()
    _save(fig, output_dir / "victim-ordering-bar")


# ── Figure 3: Interference Mode Comparison ────────────────────────────────────

def plot_mode_comparison(rows, output_dir: Path, match_mean_rps: int = 200):
    """Side-by-side P99.99 amplification of compose-post under 3 modes at matched mean load."""
    modes = ["sustained-ramp", "burst", "churn"]
    labels = {"sustained-ramp": "Sustained\nRamp", "burst": "Burst\n(1500 RPS peak)", "churn": "Connection\nChurn"}

    fig, ax = plt.subplots(figsize=(9, 5))
    x     = np.arange(len(modes))
    width = 0.5

    amps  = []
    for mode in modes:
        vals = [r["amplification_x"] for r in rows
                if r["mode"] == mode and r["endpoint"] == "compose-post"
                and r["metric"] == "p99_99"
                and (mode != "sustained-ramp" or r["noisy_rps"] == match_mean_rps)]
        amps.append(np.median(vals) if vals else 0)

    bars = ax.bar(x, amps, width,
                  color=[MODE_COLORS[m] for m in modes], alpha=0.85)
    for bar, v in zip(bars, amps):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width() / 2,
                    bar.get_height() + 0.05, f"{v:.1f}×",
                    ha="center", va="bottom", fontsize=11, fontweight="bold")

    ax.axhline(y=1.0, color="#27ae60", linestyle="--", linewidth=1.5, label="Baseline (1×)")
    ax.set_xticks(x)
    ax.set_xticklabels([labels[m] for m in modes], fontsize=11)
    ax.set_ylabel("P99.99 Amplification (×baseline)", fontsize=11)
    ax.set_title(f"Experiment 13 — Interference Mode Comparison\n"
                 f"compose-post P99.99 at Matched Mean {match_mean_rps} RPS Noisy Load",
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=9)
    ax.grid(axis="y", alpha=0.3, linestyle="--")
    ax.set_ylim(bottom=0)
    fig.tight_layout()
    _save(fig, output_dir / "interference-mode-comparison")


# ── Figure 4: ztunnel CPU over time ──────────────────────────────────────────

def plot_ztunnel_cpu(ztunnel_dir: Path, output_dir: Path):
    """ztunnel CPU utilization during Case A sustained-ramp."""
    times, cpus = load_ztunnel_series(ztunnel_dir, "A", "sustained-ramp")

    if not times:
        _placeholder(output_dir / "ztunnel-cpu-over-time.png",
                     "ztunnel CPU Over Time\nNo data yet — run Case A sustained-ramp trials")
        return

    fig, ax = plt.subplots(figsize=(11, 5))
    ax.plot(times, cpus, "-", color="#9b59b6", linewidth=2, label="ztunnel CPU (median across trials)")
    ax.fill_between(times, cpus, alpha=0.15, color="#9b59b6")
    for ref, lbl in [(500, "500m (½ core)"), (1000, "1 core"), (2000, "2 cores")]:
        ax.axhline(y=ref, color="#bdc3c7", linestyle=":", linewidth=1)
        ax.text(max(times) * 0.98, ref + 20, lbl, ha="right", fontsize=8, color="#7f8c8d")
    ax.set_xlabel("Time since measurement start (s)", fontsize=11)
    ax.set_ylabel("ztunnel CPU (millicores)", fontsize=11)
    ax.set_title("Experiment 13 — ztunnel CPU Utilization\n"
                 "Case A (social-graph victim) · Sustained Ramp",
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=9)
    ax.grid(alpha=0.3, linestyle="--")
    ax.set_ylim(bottom=0)
    fig.tight_layout()
    _save(fig, output_dir / "ztunnel-cpu-over-time")


# ── Figure 5: Baseline vs Noisy latency bars ──────────────────────────────────

def plot_baseline_vs_noisy(rows, baseline: dict, output_dir: Path, noisy_rps: int = 700):
    """Per-endpoint P50/P99/P99.99 with and without noisy load (Case A)."""
    endpoints = ["compose-post", "home-timeline", "user-timeline"]
    pcts      = [("p50", "P50"), ("p99", "P99"), ("p99_99", "P99.99")]

    fig, axes = plt.subplots(1, 3, figsize=(16, 6), sharey=False)

    for ax, ep in zip(axes, endpoints):
        x     = np.arange(len(pcts))
        width = 0.35

        base_vals = [baseline.get((ep, m), 0) for m, _ in pcts]
        noisy_vals = []
        for m, _ in pcts:
            vals = [r["noisy_ms"] for r in rows
                    if r["case"] == "A" and r["mode"] == "sustained-ramp"
                    and r["noisy_rps"] == noisy_rps
                    and r["endpoint"] == ep and r["metric"] == m]
            noisy_vals.append(np.median(vals) if vals else 0)

        ax.bar(x - width / 2, base_vals,  width, label="No noisy (Exp12 baseline)",
               color="#27ae60", alpha=0.8)
        ax.bar(x + width / 2, noisy_vals, width, label=f"With noisy ({noisy_rps} RPS)",
               color="#e74c3c", alpha=0.8)

        ax.set_xticks(x)
        ax.set_xticklabels([l for _, l in pcts])
        ax.set_title(ep, fontsize=10, fontweight="bold")
        ax.set_ylabel("Latency (ms)" if ep == "compose-post" else "")
        ax.grid(axis="y", alpha=0.3, linestyle="--")
        ax.set_ylim(bottom=0)
        if ep == "compose-post":
            ax.legend(fontsize=8)

    fig.suptitle(f"Experiment 13 — Baseline vs Noisy Latency\n"
                 f"Case A (social-graph victim) · {noisy_rps} RPS Noisy Load",
                 fontsize=13, fontweight="bold")
    fig.tight_layout()
    _save(fig, output_dir / "baseline-vs-noisy-bars")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _save(fig, base_path: Path):
    base_path.parent.mkdir(parents=True, exist_ok=True)
    for ext in ("pdf", "png"):
        p = base_path.with_suffix(f".{ext}")
        fig.savefig(p, dpi=150, bbox_inches="tight")
        print(f"[OUTPUT] {p}")
    plt.close(fig)


def _placeholder(png_path: Path, message: str):
    png_path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(10, 4))
    ax.text(0.5, 0.55, message, ha="center", va="center",
            fontsize=14, color="#7f8c8d", transform=ax.transAxes)
    ax.text(0.5, 0.35,
            "Run the experiment first:\n  bash scripts/run/run-sustained-ramp.sh --case A",
            ha="center", va="center", fontsize=10, color="#95a5a6", transform=ax.transAxes)
    ax.set_axis_off()
    fig.tight_layout()
    fig.savefig(png_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"[OUTPUT] {png_path} (placeholder)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data",         required=True, help="results/tables/amplification.csv")
    parser.add_argument("--baseline",     required=True, help="Experiment12 results/tables/summary.csv")
    parser.add_argument("--ztunnel-dir",  required=True, help="data/raw/ directory")
    parser.add_argument("--output",       required=True, help="Output figures base directory")
    parser.add_argument("--noisy-rps",    type=int, default=700, help="Noisy RPS for bar charts")
    args = parser.parse_args()

    rows     = load_amplification(Path(args.data))
    baseline = load_baseline(Path(args.baseline))
    out      = Path(args.output)

    print(f"Loaded {len(rows)} amplification rows, {len(baseline)} baseline entries")

    plot_hero(rows,                           out / "throughput")
    plot_victim_ordering(rows, baseline,      out / "victim-ordering", args.noisy_rps)  # wrong sig, fix below
    plot_mode_comparison(rows,                out / "interference-modes")
    plot_ztunnel_cpu(Path(args.ztunnel_dir),  out / "ztunnel-cpu")
    plot_baseline_vs_noisy(rows, baseline,    out / "latency-cdf", args.noisy_rps)

    print("[DONE]")


# Fix plot_victim_ordering call signature
def plot_victim_ordering(rows, output_dir: Path, noisy_rps: int = 700):
    endpoints = ["compose-post", "home-timeline", "user-timeline"]
    cases     = ["A", "B", "C"]
    labels    = {"A": "Case A\n(social-graph)", "B": "Case B\n(user-service)", "C": "Case C\n(media-service)"}

    fig, ax = plt.subplots(figsize=(11, 6))
    x      = np.arange(len(cases))
    width  = 0.25

    for i, ep in enumerate(endpoints):
        amps = []
        for case in cases:
            vals = [r["amplification_x"] for r in rows
                    if r["case"] == case and r["mode"] == "sustained-ramp"
                    and r["noisy_rps"] == noisy_rps
                    and r["endpoint"] == ep and r["metric"] == "p99_99"]
            amps.append(np.median(vals) if vals else 0)
        bars = ax.bar(x + (i - 1) * width, amps, width,
                      label=ep, color=ENDPOINT_COLORS[ep], alpha=0.85)
        for bar, v in zip(bars, amps):
            if v > 0:
                ax.text(bar.get_x() + bar.get_width() / 2,
                        bar.get_height() + 0.05, f"{v:.1f}×",
                        ha="center", va="bottom", fontsize=8)

    ax.axhline(y=1.0, color="#27ae60", linestyle="--", linewidth=1.5, label="Baseline (1×)")
    ax.set_xticks(x)
    ax.set_xticklabels([labels[c] for c in cases])
    ax.set_ylabel("P99.99 Amplification (×baseline)", fontsize=11)
    ax.set_title(f"Experiment 13 — Victim Ordering\n"
                 f"P99.99 Amplification per Case at {noisy_rps} RPS Noisy Load",
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=9)
    ax.grid(axis="y", alpha=0.3, linestyle="--")
    ax.set_ylim(bottom=0)
    if not any(v > 0 for amps_list in [[r["amplification_x"] for r in rows
                                         if r["case"] == c and r["metric"] == "p99_99"
                                         and r["noisy_rps"] == noisy_rps]
                                        for c in cases]
               for v in amps_list):
        _placeholder(output_dir / "victim-ordering-bar.png",
                     f"Victim Ordering\nNo data at {noisy_rps} RPS yet")
        plt.close(fig)
        return
    fig.tight_layout()
    _save(fig, output_dir / "victim-ordering-bar")


if __name__ == "__main__":
    main()
