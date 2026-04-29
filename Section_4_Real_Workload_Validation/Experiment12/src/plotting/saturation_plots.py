#!/usr/bin/env python3
"""
Saturation sweep plotter for Experiment 12.
Produces a single clean figure: P99 vs RPS for compose-post.
Identifies the saturation knee and annotates the paper operating point.

Usage:
  python3 saturation_plots.py --data data/raw/saturation-sweep/ --output results/figures/throughput/
"""

import re
import argparse
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from pathlib import Path


# Actual baseline operating point chosen after the sweep
OPERATE_POINTS = {
    "compose-post":  50,
    "home-timeline": 100,
    "user-timeline": 100,
}

COLORS = {
    "compose-post":  "#e74c3c",
    "home-timeline": "#3498db",
    "user-timeline": "#2ecc71",
}


def parse_p99_from_txt(filepath: Path) -> float | None:
    """Extract P99 latency (ms) from a wrk2 output file.
    Handles wrk2's 3-decimal percentage format (99.000%) and
    unit suffixes: ms, us, s, m (minutes).
    """
    try:
        content = filepath.read_text()
    except FileNotFoundError:
        return None
    for line in content.splitlines():
        # wrk2 outputs "99.000%" (3 dp), NOT "99.000000%"
        if "99.000%" in line and "99.000%%" not in line:
            parts = line.strip().split()
            if len(parts) >= 2:
                val_str = parts[1]
                try:
                    if val_str.endswith("ms"):
                        return float(val_str[:-2])
                    elif val_str.endswith("us"):
                        return float(val_str[:-2]) / 1000.0
                    elif val_str.endswith("m"):        # minutes
                        return float(val_str[:-1]) * 60_000.0
                    elif val_str.endswith("s"):
                        return float(val_str[:-1]) * 1000.0
                except ValueError:
                    pass
    return None


def plot_saturation_sweep(sweep_dir: Path, output_dir: Path):
    """Plot P99 vs RPS for each endpoint that has sweep data."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Discover which endpoints actually have sweep files
    all_endpoints = list(OPERATE_POINTS.keys())
    endpoints_with_data = []
    endpoint_data = {}

    for endpoint in all_endpoints:
        pattern = f"{endpoint}-*rps.txt"
        files = sorted(
            sweep_dir.glob(pattern),
            key=lambda f: int(re.search(r"(\d+)rps", f.name).group(1))
        )
        if not files:
            print(f"  [SKIP] {endpoint}: no sweep files found")
            continue

        rps_vals, p99_vals = [], []
        for f in files:
            m = re.search(r"(\d+)rps", f.name)
            if not m:
                continue
            rps = int(m.group(1))
            p99 = parse_p99_from_txt(f)
            if p99 is not None:
                rps_vals.append(rps)
                p99_vals.append(p99)
            else:
                print(f"  [WARN] Could not parse P99 from {f.name}")

        if not rps_vals:
            print(f"  [SKIP] {endpoint}: files found but all failed to parse")
            continue

        endpoints_with_data.append(endpoint)
        endpoint_data[endpoint] = (rps_vals, p99_vals)
        print(f"  [OK]   {endpoint}: {len(rps_vals)} RPS points, "
              f"P99 range {min(p99_vals):.0f}–{max(p99_vals):.0f} ms")

    if not endpoints_with_data:
        print("[ERROR] No sweep data found — check --data path")
        return

    n = len(endpoints_with_data)
    fig, axes = plt.subplots(1, n, figsize=(7 * n, 5), squeeze=False)
    axes = axes[0]

    for ax, endpoint in zip(axes, endpoints_with_data):
        rps_vals, p99_vals = endpoint_data[endpoint]
        color = COLORS.get(endpoint, "#555")

        # Convert ms → seconds for readability on the Y-axis
        p99_s = [v / 1000.0 for v in p99_vals]

        ax.plot(rps_vals, p99_s, "o-", color=color,
                linewidth=2.5, markersize=7, label="P99 latency")

        # Shade the saturated region (P99 > 1 s)
        knee_rps = None
        for i, (r, p) in enumerate(zip(rps_vals, p99_s)):
            if p > 1.0 and knee_rps is None:
                knee_rps = r
        if knee_rps:
            ax.axvspan(knee_rps, max(rps_vals) + 20, alpha=0.08,
                       color="#e74c3c", label="Saturated region")
            ax.axvline(x=knee_rps, color="#e74c3c", linestyle=":",
                       linewidth=1.5, label=f"Knee ≈ {knee_rps} RPS")

        # Mark chosen operating point
        op_rps = OPERATE_POINTS[endpoint]
        ax.axvline(x=op_rps, color="#27ae60", linestyle="--",
                   linewidth=2, label=f"Baseline op. point ({op_rps} RPS)")

        # Annotate P99 at operating point
        if op_rps in rps_vals:
            op_p99 = p99_s[rps_vals.index(op_rps)]
            ax.annotate(f"  {op_p99*1000:.0f} ms",
                        xy=(op_rps, op_p99),
                        fontsize=9, color="#27ae60", va="bottom")

        ax.set_xlabel("Offered Load (RPS)", fontsize=11)
        ax.set_ylabel("P99 Latency (s)", fontsize=11)
        ax.set_title(f"{endpoint}", fontsize=12, fontweight="bold")
        ax.legend(fontsize=8, loc="upper left")
        ax.grid(alpha=0.3, linestyle="--")
        ax.set_xlim(left=0, right=max(rps_vals) + 30)
        ax.set_ylim(bottom=0)
        ax.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.1f s"))

    fig.suptitle(
        "Experiment 12: Saturation Sweep — P99 Latency vs Offered Load\n"
        "(DeathStarBench Social Network · Istio Ambient Mesh · worker-0 4 vCPU)",
        fontsize=13, fontweight="bold", y=1.02
    )
    fig.tight_layout()

    out_pdf = output_dir / "saturation-sweep.pdf"
    out_png = output_dir / "saturation-sweep.png"
    fig.savefig(out_pdf, dpi=150, bbox_inches="tight")
    fig.savefig(out_png, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"[OUTPUT] {out_pdf}")
    print(f"[OUTPUT] {out_png}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True,
                        help="data/raw/saturation-sweep/ directory")
    parser.add_argument("--output", required=True,
                        help="Output directory for figures")
    args = parser.parse_args()

    plot_saturation_sweep(Path(args.data), Path(args.output))
    print("[DONE]")
