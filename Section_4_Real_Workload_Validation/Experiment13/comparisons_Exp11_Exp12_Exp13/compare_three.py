#!/usr/bin/env python3
"""
Three-way comparison: Exp11 (plain K8s) vs Exp12 (Ambient) vs Exp13 (noisy neighbor).

Generates:
  tables/  — 3 CSV files
  figures/ — 5 figures (pdf + png)

Usage:
  python3 compare_three.py \
      --exp11 ../Experiment11/results/tables/summary.csv \
      --exp12 ../Experiment12/results/tables/summary.csv \
      --amp13 results/tables/amplification.csv \
      --output comparisons_Exp11_Exp12_Exp13/
"""

import argparse, csv, sys
from collections import defaultdict
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ── Constants ─────────────────────────────────────────────────────────────────
ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
METRICS   = ["p50", "p75", "p90", "p99", "p99_9", "p99_99"]
DISPLAY   = {"p50":"P50","p75":"P75","p90":"P90","p99":"P99","p99_9":"P99.9","p99_99":"P99.99"}

EXP_COLORS  = {"Exp11 (plain K8s)": "#2ecc71", "Exp12 (Ambient)": "#3498db", "Exp13 (noisy)": "#e74c3c"}
EXP_HATCHES = {"Exp11 (plain K8s)": "",        "Exp12 (Ambient)": "//",      "Exp13 (noisy)": "xx"}
EP_COLORS   = {"compose-post": "#e74c3c", "home-timeline": "#3498db", "user-timeline": "#2ecc71"}


# ── Loaders ───────────────────────────────────────────────────────────────────

def load_summary(path: Path) -> dict:
    """Returns {(endpoint, metric): median_ms}"""
    b = {}
    if not path.exists():
        return b
    for row in csv.DictReader(open(path)):
        ep, met = row.get("endpoint",""), row.get("metric","")
        val = row.get("median_ms","")
        if ep and met and val:
            try: b[(ep, met)] = float(val)
            except ValueError: pass
    return b


def load_amp(path: Path) -> list[dict]:
    rows = []
    if not path.exists():
        return rows
    for row in csv.DictReader(open(path)):
        try:
            row["noisy_rps"]       = int(row["noisy_rps"])
            row["amplification_x"] = float(row["amplification_x"])
            row["baseline_ms"]     = float(row["baseline_ms"])
            row["noisy_ms"]        = float(row["noisy_ms"])
            rows.append(row)
        except (ValueError, KeyError): pass
    return rows


def get_exp13_at_rps(amp_rows, noisy_rps, case="A", mode="sustained-ramp"):
    """Returns {(endpoint, metric): median_noisy_ms} for a specific RPS level."""
    groups = defaultdict(list)
    for r in amp_rows:
        if r["case"] == case and r["mode"] == mode and r["noisy_rps"] == noisy_rps:
            groups[(r["endpoint"], r["metric"])].append(r["noisy_ms"])
    return {k: float(np.median(v)) for k, v in groups.items()}


# ── Table 1: three_way_latency.csv ───────────────────────────────────────────

def write_three_way_table(exp11, exp12, exp13_at_rps, noisy_rps, out_dir):
    path = out_dir / "tables" / "three_way_latency.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["endpoint","metric",
              "exp11_plain_ms","exp12_ambient_ms",f"exp13_noisy_{noisy_rps}rps_ms",
              "mesh_overhead_ms","mesh_overhead_pct",
              "noisy_overhead_ms","noisy_overhead_pct"]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for ep in ENDPOINTS:
            for met in METRICS:
                e11 = exp11.get((ep, met))
                e12 = exp12.get((ep, met))
                e13 = exp13_at_rps.get((ep, met))
                row = {"endpoint": ep, "metric": met}
                row["exp11_plain_ms"]   = round(e11, 2) if e11 else "N/A"
                row["exp12_ambient_ms"] = round(e12, 2) if e12 else "N/A"
                row[f"exp13_noisy_{noisy_rps}rps_ms"] = round(e13, 2) if e13 else "N/A"
                if e11 and e12:
                    d = e12 - e11
                    row["mesh_overhead_ms"]  = round(d, 2)
                    row["mesh_overhead_pct"] = round(d / e11 * 100, 1)
                else:
                    row["mesh_overhead_ms"] = row["mesh_overhead_pct"] = "N/A"
                if e12 and e13:
                    d = e13 - e12
                    row["noisy_overhead_ms"]  = round(d, 2)
                    row["noisy_overhead_pct"] = round(d / e12 * 100, 1)
                else:
                    row["noisy_overhead_ms"] = row["noisy_overhead_pct"] = "N/A"
                w.writerow(row)
    print(f"[TABLE] {path}")


# ── Table 2: mesh_tax.csv ────────────────────────────────────────────────────

def write_mesh_tax(exp11, exp12, out_dir):
    path = out_dir / "tables" / "mesh_tax.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["endpoint","metric","plain_ms","ambient_ms","delta_ms","overhead_pct"]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for ep in ENDPOINTS:
            for met in METRICS:
                e11 = exp11.get((ep, met))
                e12 = exp12.get((ep, met))
                row = {"endpoint": ep, "metric": met}
                row["plain_ms"]   = round(e11, 2) if e11 else "N/A"
                row["ambient_ms"] = round(e12, 2) if e12 else "N/A"
                if e11 and e12:
                    d = e12 - e11
                    row["delta_ms"]     = round(d, 2)
                    row["overhead_pct"] = round(d / e11 * 100, 1)
                else:
                    row["delta_ms"] = row["overhead_pct"] = "N/A"
                w.writerow(row)
    print(f"[TABLE] {path}")


# ── Table 3: cumulative_overhead.csv ─────────────────────────────────────────

def write_cumulative(exp11, exp12, exp13_at_rps, noisy_rps, out_dir):
    path = out_dir / "tables" / "cumulative_overhead.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["endpoint","metric","plain_ms","ambient_ms","noisy_ms",
              "mesh_tax_pct","noisy_tax_pct","total_tax_pct"]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for ep in ENDPOINTS:
            for met in ["p50","p99","p99_99"]:
                e11 = exp11.get((ep, met))
                e12 = exp12.get((ep, met))
                e13 = exp13_at_rps.get((ep, met))
                row = {"endpoint": ep, "metric": met}
                row["plain_ms"]   = round(e11, 2) if e11 else "N/A"
                row["ambient_ms"] = round(e12, 2) if e12 else "N/A"
                row["noisy_ms"]   = round(e13, 2) if e13 else "N/A"
                if e11 and e12:
                    row["mesh_tax_pct"] = round((e12-e11)/e11*100, 1)
                else:
                    row["mesh_tax_pct"] = "N/A"
                if e11 and e12 and e13:
                    row["noisy_tax_pct"] = round((e13-e12)/e11*100, 1)
                    row["total_tax_pct"] = round((e13-e11)/e11*100, 1)
                else:
                    row["noisy_tax_pct"] = row["total_tax_pct"] = "N/A"
                w.writerow(row)
    print(f"[TABLE] {path}")


# ── Figure 1: Three-way percentile bars ──────────────────────────────────────

def plot_three_way_bars(exp11, exp12, exp13_at_rps, noisy_rps, out_dir):
    pcts = [("p50","P50"), ("p99","P99"), ("p99_99","P99.99")]
    exps = [("Exp11 (plain K8s)", exp11),
            ("Exp12 (Ambient)",   exp12),
            ("Exp13 (noisy)",     exp13_at_rps)]

    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    for ax, ep in zip(axes, ENDPOINTS):
        x = np.arange(len(pcts))
        width = 0.25
        for i, (label, data) in enumerate(exps):
            vals = [data.get((ep, m), 0) for m, _ in pcts]
            bars = ax.bar(x + (i-1)*width, vals, width, label=label,
                         color=list(EXP_COLORS.values())[i], alpha=0.85,
                         hatch=list(EXP_HATCHES.values())[i], edgecolor="white")
            for bar, v in zip(bars, vals):
                if v > 0:
                    ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+15,
                            f"{v:.0f}", ha="center", va="bottom", fontsize=7)

        ax.set_xticks(x)
        ax.set_xticklabels([l for _, l in pcts], fontsize=11)
        ax.set_title(ep, fontsize=12, fontweight="bold")
        ax.set_ylabel("Latency (ms)" if ep == ENDPOINTS[0] else "")
        ax.grid(axis="y", alpha=0.3, linestyle="--")
        ax.set_ylim(bottom=0)
        if ep == ENDPOINTS[0]:
            ax.legend(fontsize=9)

    fig.suptitle(
        f"Three-Way Comparison: Plain K8s → Ambient Mesh → Noisy Neighbor ({noisy_rps} RPS)\n"
        "DeathStarBench Social Network — Latency Percentiles per Endpoint",
        fontsize=13, fontweight="bold")
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "three_way_percentile_bars")


# ── Figure 2: Stacked overhead waterfall ─────────────────────────────────────

def plot_overhead_waterfall(exp11, exp12, exp13_at_rps, noisy_rps, out_dir):
    pcts = [("p50","P50"), ("p99","P99"), ("p99_99","P99.99")]
    fig, axes = plt.subplots(1, 3, figsize=(18, 6))

    for ax, ep in zip(axes, ENDPOINTS):
        x = np.arange(len(pcts))
        width = 0.5
        base_vals, mesh_deltas, noisy_deltas = [], [], []
        for m, _ in pcts:
            e11 = exp11.get((ep, m), 0)
            e12 = exp12.get((ep, m), 0)
            e13 = exp13_at_rps.get((ep, m), 0)
            base_vals.append(e11)
            mesh_deltas.append(max(0, e12-e11) if e11 else 0)
            noisy_deltas.append(max(0, e13-e12) if e12 else 0)

        ax.bar(x, base_vals, width, label="Plain K8s (Exp11)",
               color="#2ecc71", alpha=0.85)
        ax.bar(x, mesh_deltas, width, bottom=base_vals,
               label="+ Mesh overhead (Exp12−11)", color="#3498db", alpha=0.85, hatch="//")
        bottoms2 = [b+m for b,m in zip(base_vals, mesh_deltas)]
        ax.bar(x, noisy_deltas, width, bottom=bottoms2,
               label="+ Noisy overhead (Exp13−12)", color="#e74c3c", alpha=0.85, hatch="xx")

        # Percentage annotations
        for i, (b, m, n) in enumerate(zip(base_vals, mesh_deltas, noisy_deltas)):
            if b > 0 and m > 0:
                ax.text(i, b+m/2, f"+{m/b*100:.0f}%", ha="center", va="center",
                        fontsize=8, color="white", fontweight="bold")
            if b > 0 and n > 0:
                ax.text(i, b+m+n/2, f"+{n/b*100:.0f}%", ha="center", va="center",
                        fontsize=8, color="white", fontweight="bold")

        ax.set_xticks(x)
        ax.set_xticklabels([l for _, l in pcts], fontsize=11)
        ax.set_title(ep, fontsize=12, fontweight="bold")
        ax.set_ylabel("Latency (ms)" if ep == ENDPOINTS[0] else "")
        ax.grid(axis="y", alpha=0.3, linestyle="--")
        ax.set_ylim(bottom=0)
        if ep == ENDPOINTS[0]:
            ax.legend(fontsize=8, loc="upper left")

    fig.suptitle(
        f"Overhead Decomposition: Plain K8s → Ambient → Noisy ({noisy_rps} RPS)\n"
        "Stacked latency showing incremental cost at each layer",
        fontsize=13, fontweight="bold")
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "overhead_waterfall")


# ── Figure 3: Mesh tax bar chart (Exp11 vs Exp12 only) ──────────────────────

def plot_mesh_tax(exp11, exp12, out_dir):
    pcts = [("p50","P50"), ("p99","P99"), ("p99_99","P99.99")]
    fig, ax = plt.subplots(figsize=(12, 6))
    x = np.arange(len(ENDPOINTS))
    width = 0.25

    for i, (met, label) in enumerate(pcts):
        overheads = []
        for ep in ENDPOINTS:
            e11 = exp11.get((ep, met), 0)
            e12 = exp12.get((ep, met), 0)
            overheads.append(round((e12-e11)/e11*100, 1) if e11 else 0)
        bars = ax.bar(x + (i-1)*width, overheads, width, label=label,
                     color=["#f39c12","#e74c3c","#8e44ad"][i], alpha=0.85)
        for bar, v in zip(bars, overheads):
            ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.5,
                    f"{v:.1f}%", ha="center", va="bottom", fontsize=9)

    ax.axhline(0, color="black", linewidth=0.8)
    ax.set_xticks(x)
    ax.set_xticklabels(ENDPOINTS, fontsize=11)
    ax.set_ylabel("Mesh Overhead (%)", fontsize=11)
    ax.set_title("Istio Ambient Mesh Tax\n"
                 "Exp12 (Ambient) vs Exp11 (plain K8s) — % increase in latency",
                 fontsize=13, fontweight="bold")
    ax.legend(fontsize=10)
    ax.grid(axis="y", alpha=0.3, linestyle="--")
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "mesh_tax_bars")


# ── Figure 4: Amplification across all 3 experiments ─────────────────────────

def plot_three_exp_amplification(exp11, exp12, amp_rows, out_dir):
    """For each noisy RPS level: show Exp11 (1.0×), Exp12 (mesh overhead ×),
    Exp13 (noisy amplification ×) — all relative to Exp11 as the true baseline.

    Note: if Exp12 < Exp11 (mesh is faster), mesh_amp < 1.0.
    The axhspan and annotations handle both directions correctly.
    """
    # sharey=False: each endpoint has very different amplification scale
    fig, axes = plt.subplots(1, 3, figsize=(18, 5), sharey=False)

    for ax, ep in zip(axes, ENDPOINTS):
        # Exp12 overhead relative to Exp11 (may be < 1.0 if mesh is faster)
        e11_p99 = exp11.get((ep, "p99_99"), 0)
        e12_p99 = exp12.get((ep, "p99_99"), 0)
        mesh_amp = e12_p99 / e11_p99 if e11_p99 else 1.0

        # Exp13 by noisy RPS (Case A, sustained-ramp), relative to Exp11
        pts: dict = defaultdict(list)
        for r in amp_rows:
            if (r["case"] == "A" and r["mode"] == "sustained-ramp"
                    and r["endpoint"] == ep and r["metric"] == "p99_99"):
                pts[r["noisy_rps"]].append(r["noisy_ms"])

        rps_levels = sorted(pts.keys())
        exp13_amps = [
            float(np.median(pts[r])) / e11_p99
            if e11_p99 else float(np.median(pts[r])) / e12_p99
            for r in rps_levels
        ]

        # Plot Exp13 curve
        if rps_levels:
            ax.plot(rps_levels, exp13_amps, "o-", color="#e74c3c", linewidth=2.5,
                    markersize=7, label="Exp13 (noisy) vs Exp11", zorder=3)
            # Shade region between Exp13 curve and the Exp11 baseline
            ax.fill_between(rps_levels, 1.0, exp13_amps, alpha=0.10, color="#e74c3c")

        # Exp12 fixed horizontal line
        ax.axhline(mesh_amp, color="#3498db", linestyle="-.", linewidth=2,
                   label=f"Exp12 (Ambient) = {mesh_amp:.2f}×")

        # Exp11 baseline
        ax.axhline(1.0, color="#2ecc71", linestyle="--", linewidth=1.5,
                   label="Exp11 (plain K8s) = 1.0×")

        # Shade the band between Exp11 baseline and Exp12 line
        lo, hi = min(1.0, mesh_amp), max(1.0, mesh_amp)
        ax.axhspan(lo, hi, alpha=0.08, color="#3498db")

        # Sensible y-axis: always show 0, leave 20% headroom above max point
        all_ys = exp13_amps + [mesh_amp, 1.0]
        y_top = max(all_ys) * 1.25 if all_ys else 2.0
        ax.set_ylim(0, max(y_top, 1.5))

        ax.set_xlabel("Noisy Load (RPS)", fontsize=10)
        ax.set_ylabel("Amplification (× Exp11 baseline)", fontsize=10)
        ax.set_title(ep, fontsize=11, fontweight="bold")
        ax.grid(alpha=0.3, linestyle="--")
        # Legend on every panel
        ax.legend(fontsize=8, loc="upper left")

    fig.suptitle(
        "Three-Way Amplification: Everything Relative to Plain K8s (Exp11)\n"
        "P99.99 · Case A · Sustained Ramp",
        fontsize=13, fontweight="bold")
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "three_exp_amplification")


# ── Figure 5: Radar chart — P50/P99/P99.99 per endpoint ─────────────────────

def plot_radar(exp11, exp12, exp13_at_rps, noisy_rps, out_dir):
    from matplotlib.patches import FancyBboxPatch
    metrics = [("p50","P50"),("p99","P99"),("p99_99","P99.99")]
    categories = [f"{ep}\n{label}" for ep in ENDPOINTS for _,label in metrics]
    N = len(categories)
    angles = [n/float(N)*2*np.pi for n in range(N)]
    angles += angles[:1]

    fig, ax = plt.subplots(figsize=(10, 10), subplot_kw=dict(polar=True))
    for label, data, color in [
        ("Exp11 (plain K8s)", exp11, "#2ecc71"),
        ("Exp12 (Ambient)",   exp12, "#3498db"),
        (f"Exp13 (noisy {noisy_rps})", exp13_at_rps, "#e74c3c"),
    ]:
        values = [data.get((ep, m), 0) for ep in ENDPOINTS for m, _ in metrics]
        values += values[:1]
        ax.plot(angles, values, "o-", color=color, linewidth=2, label=label)
        ax.fill(angles, values, alpha=0.1, color=color)

    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(categories, fontsize=8)
    ax.set_title(
        f"Latency Radar: All 3 Experiments\n(Noisy @ {noisy_rps} RPS · Case A)",
        fontsize=13, fontweight="bold", y=1.08)
    ax.legend(loc="upper right", bbox_to_anchor=(1.3, 1.1), fontsize=9)
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "three_exp_radar")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _save(fig, base: Path):
    base.parent.mkdir(parents=True, exist_ok=True)
    for ext in ("pdf", "png"):
        p = base.with_suffix(f".{ext}")
        fig.savefig(p, dpi=150, bbox_inches="tight")
        print(f"[FIGURE] {p}")
    plt.close(fig)


def _placeholder(out_dir, name, msg):
    fig, ax = plt.subplots(figsize=(10, 4))
    ax.text(0.5, 0.5, msg, ha="center", va="center", fontsize=14, color="#7f8c8d",
            transform=ax.transAxes)
    ax.set_axis_off()
    fig.tight_layout()
    _save(fig, out_dir / "figures" / name)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Three-way comparison: Exp11 vs Exp12 vs Exp13")
    parser.add_argument("--exp11", required=True, help="Exp11 results/tables/summary.csv")
    parser.add_argument("--exp12", required=True, help="Exp12 results/tables/summary.csv")
    parser.add_argument("--amp13", required=True, help="Exp13 results/tables/amplification.csv")
    parser.add_argument("--output", required=True, help="Output directory")
    parser.add_argument("--noisy-rps", type=int, default=700, help="Noisy RPS for Exp13 bars")
    args = parser.parse_args()

    out = Path(args.output)
    exp11 = load_summary(Path(args.exp11))
    exp12 = load_summary(Path(args.exp12))
    amp_rows = load_amp(Path(args.amp13))

    if not exp11:
        print(f"[WARN] Exp11 data not found at {args.exp11} — "
              "mesh_tax and three-way figures will show N/A for plain K8s.\n"
              "       Run Experiment 11 first, then re-run this script.")
    if not exp12:
        sys.exit(f"[ERROR] Exp12 summary not found: {args.exp12}")

    exp13_at_rps = get_exp13_at_rps(amp_rows, args.noisy_rps)
    print(f"Loaded: Exp11={len(exp11)} entries, Exp12={len(exp12)}, "
          f"Exp13 amp={len(amp_rows)} rows, Exp13@{args.noisy_rps}RPS={len(exp13_at_rps)}")

    # Tables
    write_three_way_table(exp11, exp12, exp13_at_rps, args.noisy_rps, out)
    write_mesh_tax(exp11, exp12, out)
    write_cumulative(exp11, exp12, exp13_at_rps, args.noisy_rps, out)

    # Figures (all real data — Exp11 is now available)
    plot_three_way_bars(exp11, exp12, exp13_at_rps, args.noisy_rps, out)
    plot_overhead_waterfall(exp11, exp12, exp13_at_rps, args.noisy_rps, out)
    plot_mesh_tax(exp11, exp12, out)
    plot_three_exp_amplification(exp11, exp12, amp_rows, out)
    plot_radar(exp11, exp12, exp13_at_rps, args.noisy_rps, out)

    print(f"\n[DONE] All outputs → {out}")


if __name__ == "__main__":
    main()
