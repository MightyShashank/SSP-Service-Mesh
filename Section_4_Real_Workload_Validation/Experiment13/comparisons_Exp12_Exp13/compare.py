#!/usr/bin/env python3
"""
Experiment 12 vs Experiment 13 — Comparison Suite
===================================================
Generates 3 CSV tables and 4 figures comparing the ambient mesh baseline
(Exp12) with the noisy-neighbor interference results (Exp13).

All outputs go into this script's own directory:
  comparisons_Exp12_Exp13/tables/
  comparisons_Exp12_Exp13/figures/

Usage (run from Experiment13 root):
  python3 comparisons_Exp12_Exp13/compare.py \\
      --baseline ../Experiment12/results/tables/summary.csv \\
      --amp      results/tables/amplification.csv \\
      --output   comparisons_Exp12_Exp13/
"""

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ── Palette ──────────────────────────────────────────────────────────────────
CASE_COLORS = {"A": "#e74c3c", "B": "#3498db", "C": "#2ecc71"}
EP_COLORS   = {
    "compose-post":  "#e74c3c",
    "home-timeline": "#3498db",
    "user-timeline": "#2ecc71",
}
MODE_COLORS = {
    "sustained-ramp": "#e74c3c",
    "burst":          "#9b59b6",
    "churn":          "#f39c12",
}
ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
METRICS   = ["p50", "p99", "p99_99"]

# ── Loaders ───────────────────────────────────────────────────────────────────

def load_baseline(path: Path) -> dict:
    """Returns {(endpoint, metric): median_ms}"""
    b = {}
    for row in csv.DictReader(open(path)):
        ep, met = row.get("endpoint",""), row.get("metric","")
        val = row.get("median_ms","")
        if ep and met and val:
            try:
                b[(ep, met)] = float(val)
            except ValueError:
                pass
    return b


def load_amp(path: Path) -> list[dict]:
    rows = []
    for row in csv.DictReader(open(path)):
        try:
            row["noisy_rps"]       = int(row["noisy_rps"])
            row["amplification_x"] = float(row["amplification_x"])
            row["baseline_ms"]     = float(row["baseline_ms"])
            row["noisy_ms"]        = float(row["noisy_ms"])
            rows.append(row)
        except (ValueError, KeyError):
            pass
    return rows


# ── Table 1: overhead_table.csv ───────────────────────────────────────────────

def write_overhead_table(baseline: dict, amp_rows: list, out_dir: Path):
    """
    For every (case, mode, noisy_rps, endpoint, metric) group compute
    median noisy latency and write side-by-side with baseline.
    """
    path = out_dir / "tables" / "overhead_table.csv"
    path.parent.mkdir(parents=True, exist_ok=True)

    fields = ["case","mode","noisy_rps","endpoint","metric",
              "baseline_ms","median_noisy_ms","delta_ms","amplification_x"]

    # group amp_rows
    groups = defaultdict(list)
    for r in amp_rows:
        key = (r["case"], r["mode"], r["noisy_rps"], r["endpoint"], r["metric"])
        groups[key].append(r["noisy_ms"])

    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for key in sorted(groups):
            case, mode, nrps, ep, met = key
            b_ms   = baseline.get((ep, met), float("nan"))
            n_ms   = float(np.median(groups[key]))
            w.writerow({
                "case": case, "mode": mode, "noisy_rps": nrps,
                "endpoint": ep, "metric": met,
                "baseline_ms":    round(b_ms, 2),
                "median_noisy_ms": round(n_ms, 2),
                "delta_ms":        round(n_ms - b_ms, 2),
                "amplification_x": round(n_ms / b_ms, 3) if b_ms else "NA",
            })
    print(f"[TABLE] {path}")


# ── Table 2: amplification_pivot.csv ─────────────────────────────────────────

def write_amp_pivot(amp_rows: list, out_dir: Path,
                    metric="p99_99", mode="sustained-ramp", endpoint="compose-post"):
    """
    Pivot: rows = noisy_rps, columns = Case A / B / C
    """
    path = out_dir / "tables" / "amplification_pivot.csv"
    path.parent.mkdir(parents=True, exist_ok=True)

    data = defaultdict(dict)  # {noisy_rps: {case: amp}}
    for r in amp_rows:
        if r["metric"] == metric and r["mode"] == mode and r["endpoint"] == endpoint:
            nrps = r["noisy_rps"]
            case = r["case"]
            data[nrps].setdefault(case, []).append(r["amplification_x"])

    cases = sorted({r["case"] for r in amp_rows})
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["noisy_rps"] + [f"case_{c}" for c in cases])
        w.writeheader()
        for nrps in sorted(data):
            row = {"noisy_rps": nrps}
            for c in cases:
                vals = data[nrps].get(c, [])
                row[f"case_{c}"] = round(float(np.median(vals)), 3) if vals else ""
            w.writerow(row)
    print(f"[TABLE] {path}  (pivot: {endpoint} {metric}, {mode})")


# ── Table 3: summary_comparison.csv ──────────────────────────────────────────

def write_summary_comparison(baseline: dict, amp_rows: list, out_dir: Path,
                              noisy_rps: int = 700):
    """
    For a fixed noisy_rps: Exp12 baseline vs median Exp13 (all cases, all endpoints,
    P50/P99/P99.99).
    """
    path = out_dir / "tables" / "summary_comparison.csv"
    path.parent.mkdir(parents=True, exist_ok=True)

    groups = defaultdict(list)  # {(case, ep, met): [noisy_ms]}
    for r in amp_rows:
        if r["noisy_rps"] == noisy_rps and r["mode"] == "sustained-ramp":
            groups[(r["case"], r["endpoint"], r["metric"])].append(r["noisy_ms"])

    fields = ["case","endpoint","metric","exp12_baseline_ms",
              f"exp13_noisy_{noisy_rps}rps_ms","amplification_x"]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for case in sorted({r["case"] for r in amp_rows}):
            for ep in ENDPOINTS:
                for met in METRICS:
                    vals = groups.get((case, ep, met), [])
                    b_ms = baseline.get((ep, met), float("nan"))
                    n_ms = float(np.median(vals)) if vals else float("nan")
                    w.writerow({
                        "case": case, "endpoint": ep, "metric": met,
                        "exp12_baseline_ms": round(b_ms, 2),
                        f"exp13_noisy_{noisy_rps}rps_ms": round(n_ms, 2),
                        "amplification_x": round(n_ms / b_ms, 3) if b_ms and not np.isnan(n_ms) else "NA",
                    })
    print(f"[TABLE] {path}  (at {noisy_rps} RPS noisy, sustained-ramp)")


# ── Figure 1: Amplification curves — P99.99 vs noisy RPS, all cases ──────────

def plot_amp_curves(amp_rows: list, baseline: dict, out_dir: Path):
    # sharey=False: each case can have very different peak amplification
    fig, axes = plt.subplots(1, 3, figsize=(18, 5), sharey=False)
    cases = ["A", "B", "C"]
    labels = {"A": "Case A — social-graph", "B": "Case B — user-service",
              "C": "Case C — media-service"}

    for ax, case in zip(axes, cases):
        has_data = False
        for ep in ENDPOINTS:
            pts = [(r["noisy_rps"], r["amplification_x"])
                   for r in amp_rows
                   if r["case"] == case and r["mode"] == "sustained-ramp"
                   and r["endpoint"] == ep and r["metric"] == "p99_99"]
            if not pts:
                continue
            pts.sort()
            xs, ys = zip(*pts)
            ax.plot(xs, ys, "o-", color=EP_COLORS[ep], linewidth=2,
                    markersize=6, label=ep)
            has_data = True

        ax.axhline(1.0, color="#27ae60", linestyle="--", linewidth=1.5,
                   label="Baseline (1×)")
        ax.axhspan(0, 1.0, alpha=0.04, color="#27ae60")
        ax.set_title(labels[case], fontsize=11, fontweight="bold")
        ax.set_xlabel("Noisy Load (RPS)", fontsize=10)
        ax.set_ylabel("P99.99 Amplification (×baseline)", fontsize=10)
        ax.grid(alpha=0.3, linestyle="--")
        ax.set_ylim(bottom=0)
        # legend on every panel
        ax.legend(fontsize=8, loc="upper left")

    fig.suptitle(
        "Experiment 12 → 13: P99.99 Amplification vs Noisy Load\n"
        "(Sustained Ramp · Istio Ambient Mesh · All Victim Cases)",
        fontsize=13, fontweight="bold"
    )
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "amplification_curves")


# ── Figure 2: Percentile comparison bars — Exp12 vs Exp13 @ fixed noisy RPS ──

def plot_percentile_comparison(amp_rows: list, baseline: dict,
                                out_dir: Path, noisy_rps: int = 700):
    pcts = [("p50","P50"), ("p99","P99"), ("p99_99","P99.99")]
    cases = sorted({r["case"] for r in amp_rows})

    # Human-readable service description per victim case
    CASE_DESC = {
        "A": "Case A\n(social-graph)",
        "B": "Case B\n(user-service)",
        "C": "Case C\n(media-service)",
    }
    # Legend label for the Exp13 bar — includes case so Case B/C are explicitly named
    CASE_NOISY_LABEL = {
        "A": f"Exp13 noisy @ {noisy_rps} RPS (Case A)",
        "B": f"Exp13 noisy @ {noisy_rps} RPS (Case B)",
        "C": f"Exp13 noisy @ {noisy_rps} RPS (Case C)",
    }

    # sharey=False: each endpoint row needs its own Y scale (compose-post >> user-timeline)
    fig, axes = plt.subplots(len(ENDPOINTS), len(cases),
                             figsize=(5.5 * len(cases), 4.2 * len(ENDPOINTS)),
                             sharex="col", sharey=False)
    if len(cases) == 1:
        axes = [[ax] for ax in axes]


    for row_i, ep in enumerate(ENDPOINTS):
        for col_i, case in enumerate(cases):
            ax = axes[row_i][col_i]
            x = np.arange(len(pcts))
            width = 0.35

            base_vals  = [baseline.get((ep, m), 0) for m, _ in pcts]
            noisy_vals = []
            noisy_present = []
            for met, _ in pcts:
                vals = [r["noisy_ms"] for r in amp_rows
                        if r["case"] == case and r["mode"] == "sustained-ramp"
                        and r["noisy_rps"] == noisy_rps
                        and r["endpoint"] == ep and r["metric"] == met]
                if vals:
                    noisy_vals.append(float(np.median(vals)))
                    noisy_present.append(True)
                else:
                    noisy_vals.append(0)
                    noisy_present.append(False)

            noisy_color = CASE_COLORS.get(case, "#e74c3c")

            b_bars = ax.bar(x - width/2, base_vals, width,
                            label="Exp12 Ambient baseline",
                            color="#27ae60", alpha=0.85)
            n_bars = ax.bar(x + width/2, noisy_vals, width,
                            label=CASE_NOISY_LABEL[case],
                            color=noisy_color, alpha=0.85)

            # Amplification labels above each noisy bar
            y_max = max(max(base_vals), max(noisy_vals)) if any(noisy_vals) else max(base_vals)
            label_offset = y_max * 0.03
            for bar, bv, nv, present in zip(n_bars, base_vals, noisy_vals, noisy_present):
                if not present:
                    ax.text(bar.get_x() + bar.get_width()/2,
                            label_offset, "N/A",
                            ha="center", va="bottom", fontsize=7, color="#888888")
                elif bv > 0 and nv > 0:
                    amp = nv / bv
                    label_y = bar.get_height() + label_offset
                    ax.text(bar.get_x() + bar.get_width()/2, label_y,
                            f"{amp:.1f}×", ha="center", va="bottom",
                            fontsize=8, color="#c0392b", fontweight="bold")

            ax.set_xticks(x)
            ax.set_xticklabels([l for _, l in pcts], fontsize=10)
            ax.grid(axis="y", alpha=0.3, linestyle="--")
            ax.set_ylim(bottom=0)

            # Y-axis label: endpoint name on every first column cell
            if col_i == 0:
                ax.set_ylabel(f"{ep}\nLatency (ms)", fontsize=9, fontweight="bold")

            # Column header: case + service description (only top row)
            if row_i == 0:
                ax.set_title(CASE_DESC.get(case, f"Case {case}"),
                             fontsize=12, fontweight="bold",
                             color=noisy_color, pad=8)

            # Legend on EVERY panel so Case B (blue) and Case C (green) are labeled
            ax.legend(fontsize=7.5, loc="upper left",
                      framealpha=0.85, edgecolor="#cccccc")

    fig.suptitle(
        f"Exp12 Baseline vs Exp13 at {noisy_rps} RPS Noisy Load\n"
        "Per-Endpoint Latency Percentiles — Sustained Ramp",
        fontsize=13, fontweight="bold"
    )
    fig.tight_layout()
    _save(fig, out_dir / "figures" / f"percentile_comparison_{noisy_rps}rps")


# ── Figure 3: Amplification heatmap — Case × noisy_rps ───────────────────────

def plot_amp_heatmap(amp_rows: list, out_dir: Path,
                     metric="p99_99", mode="sustained-ramp", endpoint="compose-post"):
    # Accumulate all matching rows per (rps, case) then take median
    # (previously was dict-assign which overwrote with the last row only)
    data_lists: dict = defaultdict(lambda: defaultdict(list))
    for r in amp_rows:
        if r["metric"] == metric and r["mode"] == mode and r["endpoint"] == endpoint:
            data_lists[r["noisy_rps"]][r["case"]].append(r["amplification_x"])

    cases      = sorted({r["case"] for r in amp_rows})
    rps_levels = sorted(data_lists.keys())
    matrix = np.array([
        [float(np.median(data_lists[rps][c])) if data_lists[rps][c] else float("nan")
         for c in cases]
        for rps in rps_levels
    ])

    vmax = max(5.0, float(np.nanmax(matrix))) if not np.all(np.isnan(matrix)) else 5.0
    fig, ax = plt.subplots(figsize=(max(5, len(cases) * 2.5), max(5, len(rps_levels) * 0.7)))
    im = ax.imshow(matrix, aspect="auto", cmap="RdYlGn_r", vmin=0.5, vmax=vmax)
    cbar = fig.colorbar(im, ax=ax, shrink=0.8)
    cbar.set_label("P99.99 Amplification (×)", fontsize=10)

    ax.set_xticks(range(len(cases)))
    ax.set_xticklabels([f"Case {c}" for c in cases], fontsize=11)
    ax.set_yticks(range(len(rps_levels)))
    ax.set_yticklabels([f"{r} RPS" for r in rps_levels], fontsize=9)
    ax.set_xlabel("Victim Case", fontsize=11)
    ax.set_ylabel("Noisy Load (RPS)", fontsize=11)

    for i, rps in enumerate(rps_levels):
        for j, case in enumerate(cases):
            val = matrix[i, j]
            if not np.isnan(val):
                ax.text(j, i, f"{val:.2f}×", ha="center", va="center",
                        fontsize=9, color="white" if val > 3.5 else "black",
                        fontweight="bold")
            else:
                ax.text(j, i, "N/A", ha="center", va="center",
                        fontsize=8, color="#888888")

    ax.set_title(
        f"Amplification Heatmap — {endpoint} {metric.upper().replace('_','.')}\n"
        f"({mode} · Experiment 13 vs Experiment 12)",
        fontsize=12, fontweight="bold"
    )
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "amplification_heatmap")


# ── Figure 4: Interference mode comparison vs Exp12 ──────────────────────────

def plot_mode_vs_baseline(amp_rows: list, baseline: dict, out_dir: Path,
                          endpoint="compose-post", metric="p99_99"):
    modes = ["sustained-ramp", "burst", "churn"]
    mode_labels = {"sustained-ramp": "Sustained\nRamp",
                   "burst":          "Burst",
                   "churn":          "Connection\nChurn"}

    fig, axes = plt.subplots(1, len(modes), figsize=(15, 5), sharey=False)

    for ax, mode in zip(axes, modes):
        pts: dict = defaultdict(list)
        for r in amp_rows:
            if r["mode"] == mode and r["endpoint"] == endpoint and r["metric"] == metric:
                pts[r["noisy_rps"]].append(r["amplification_x"])

        if pts:
            xs = sorted(pts.keys())
            ys = [float(np.median(pts[x])) for x in xs]

            if len(xs) > 1:
                ax.plot(xs, ys, "o-", color=MODE_COLORS.get(mode, "#555"),
                        linewidth=2.5, markersize=7)
                ax.fill_between(xs, 1.0, ys, alpha=0.15,
                                color=MODE_COLORS.get(mode, "#555"))
                ax.set_xlabel("Noisy Load (RPS)", fontsize=10)
            else:
                bar_color = MODE_COLORS.get(mode, "#555")
                ax.bar([mode_labels[mode]], [ys[0]], color=bar_color, width=0.4, alpha=0.85)
                ax.axhspan(1.0, ys[0], alpha=0.12, color=bar_color)
                y_top = max(ys[0] * 1.12, ys[0] + 0.2)
                ax.text(0, ys[0] + 0.05, f"{ys[0]:.2f}×",
                        ha="center", va="bottom", fontsize=12,
                        fontweight="bold", color=bar_color)
                ax.set_ylim(0, max(ys[0] * 1.25, 1.5))

        ax.axhline(1.0, color="#27ae60", linestyle="--", linewidth=1.5,
                   label="Exp12 baseline (1×)")
        ax.legend(fontsize=8, loc="upper right")
        ax.set_title(mode_labels[mode], fontsize=12, fontweight="bold")
        ax.set_ylabel(f"{endpoint} P99.99\nAmplification (×baseline)", fontsize=10)
        ax.grid(alpha=0.3, linestyle="--")
        # Only reset ylim for multi-point (line) charts; single-bar charts set it explicitly above
        if not pts or len(sorted(pts.keys())) > 1:
            ax.set_ylim(bottom=0)

    fig.suptitle(
        f"Exp12 → Exp13: Interference Mode Comparison\n"
        f"{endpoint} {metric.upper().replace('_','.')} — Case A",
        fontsize=13, fontweight="bold"
    )
    fig.tight_layout()
    _save(fig, out_dir / "figures" / "mode_vs_baseline")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _save(fig, base: Path):
    base.parent.mkdir(parents=True, exist_ok=True)
    for ext in ("pdf", "png"):
        p = base.with_suffix(f".{ext}")
        fig.savefig(p, dpi=150, bbox_inches="tight")
        print(f"[FIGURE] {p}")
    plt.close(fig)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Compare Experiment 12 baseline vs Experiment 13 noisy-neighbor results"
    )
    parser.add_argument("--baseline", required=True,
                        help="Exp12 results/tables/summary.csv")
    parser.add_argument("--amp",      required=True,
                        help="Exp13 results/tables/amplification.csv")
    parser.add_argument("--output",   required=True,
                        help="Output directory (comparisons_Exp12_Exp13/)")
    parser.add_argument("--noisy-rps", type=int, default=700,
                        help="Noisy RPS for side-by-side bar chart (default: 700)")
    args = parser.parse_args()

    out = Path(args.output)
    baseline_path = Path(args.baseline)
    amp_path      = Path(args.amp)

    if not baseline_path.exists():
        sys.exit(f"[ERROR] Baseline not found: {baseline_path}")
    if not amp_path.exists():
        sys.exit(f"[ERROR] Amplification CSV not found: {amp_path}")

    baseline = load_baseline(baseline_path)
    amp_rows = load_amp(amp_path)
    print(f"Loaded {len(baseline)} baseline entries, {len(amp_rows)} amplification rows")

    # Tables
    write_overhead_table(baseline, amp_rows, out)
    write_amp_pivot(amp_rows, out)
    write_summary_comparison(baseline, amp_rows, out, noisy_rps=args.noisy_rps)

    # Figures
    plot_amp_curves(amp_rows, baseline, out)
    plot_percentile_comparison(amp_rows, baseline, out, noisy_rps=args.noisy_rps)
    plot_amp_heatmap(amp_rows, out)
    plot_mode_vs_baseline(amp_rows, baseline, out)

    print("\n[DONE] All comparison outputs written to:", out)


if __name__ == "__main__":
    main()
