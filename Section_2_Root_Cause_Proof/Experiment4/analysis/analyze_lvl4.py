import argparse
import json
import os
import re

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

plt.style.use("seaborn-v0_8-darkgrid")

plt.rcParams.update({
    "font.size": 12,
    "axes.titlesize": 14,
    "axes.labelsize": 12,
    "legend.fontsize": 10,
    "figure.figsize": (10, 6),
    "savefig.dpi": 300,
    "lines.linewidth": 2
})

colors = ["#2ca02c", "#ff7f0e", "#d62728", "#1f77b4", "#9467bd"]

# -------------------------------
# ARGUMENTS
# -------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--run_id", required=True)
args = parser.parse_args()

BASE_DIR = f"results/raw/{args.run_id}"
PLOTS_DIR = f"results/plots_lvl4/{args.run_id}"
PROC_DIR = f"results/processed/{args.run_id}"

os.makedirs(PLOTS_DIR, exist_ok=True)
os.makedirs(PROC_DIR, exist_ok=True)

LOAD_LEVELS = [0, 100, 500, 1000]

# -------------------------------
# PARSE HELPERS (shared with lvl1/2/3)
# -------------------------------
def parse_latency_decomp(log_path):
    records = []
    if not os.path.exists(log_path):
        return pd.DataFrame()
    with open(log_path) as f:
        for line in f:
            if not line.startswith("DECOMP|"):
                continue
            parts = line.strip().split("|")
            if len(parts) < 4:
                continue
            record = {"tid": int(parts[1]), "timestamp": int(parts[2])}
            for kv in parts[3:]:
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    try:
                        record[k] = int(v)
                    except ValueError:
                        record[k] = v
            records.append(record)
    return pd.DataFrame(records)


def parse_queue_delay(log_path):
    records = []
    if not os.path.exists(log_path):
        return pd.DataFrame()
    with open(log_path) as f:
        for line in f:
            if not line.startswith("QUEUE|"):
                continue
            parts = line.strip().split("|")
            if len(parts) < 4:
                continue
            tid = int(parts[1])
            ts = int(parts[2])
            delay_ns = 0
            for kv in parts[3:]:
                if kv.startswith("delay_ns="):
                    delay_ns = int(kv.split("=")[1])
            records.append({"tid": tid, "timestamp": ts, "delay_ns": delay_ns})
    return pd.DataFrame(records)


# ================================================
# PLOT 7: Queue Delay vs. Execution Time (Decoupling)
# ================================================
fig, ax = plt.subplots(figsize=(8, 8))

# For each load level, plot queue delay vs proxy total (execution proxy)
for i, load in enumerate(LOAD_LEVELS):
    phase_dir = f"{BASE_DIR}/load-{load}"

    df_decomp = parse_latency_decomp(f"{phase_dir}/latency_decomp.log")
    df_queue = parse_queue_delay(f"{phase_dir}/queue_delay.log")

    if len(df_decomp) > 0 and "T_proxy_total" in df_decomp.columns:
        proxy_us = df_decomp["T_proxy_total"].dropna() / 1000.0  # ns → μs
    else:
        proxy_us = pd.Series(dtype=float)

    if len(df_queue) > 0:
        queue_us = df_queue["delay_ns"] / 1000.0  # ns → μs
    else:
        queue_us = pd.Series(dtype=float)

    # Align lengths for scatter (take min length)
    n = min(len(proxy_us), len(queue_us), 500)  # Cap at 500 points for readability
    if n > 0:
        ax.scatter(proxy_us.values[:n], queue_us.values[:n],
                   alpha=0.4, s=15, color=colors[i % len(colors)],
                   label=f"svc-B={load} RPS")

ax.set_xlabel("T_proxy_total (μs) — Execution Time")
ax.set_ylabel("Queue Delay (μs) — Waiting Time")
ax.set_title("Queue Delay vs. Execution Time (Decoupling Plot)")

# Add diagonal reference
lims = [0, max(ax.get_xlim()[1], ax.get_ylim()[1])]
ax.plot(lims, lims, '--', color='gray', alpha=0.5, label="y = x reference")

ax.legend()
ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/queue_vs_execution.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/queue_vs_execution.png", bbox_inches="tight")
plt.close()


# ================================================
# PLOT 8: Baseline vs. Interference Comparison
# Side-by-side latency breakdown (0 RPS vs 1000 RPS)
# ================================================
fig, axes = plt.subplots(1, 2, figsize=(14, 6), sharey=True)

comparison_loads = [0, 1000]
titles = ["Baseline (svc-B = 0 RPS)", "Interference (svc-B = 1000 RPS)"]

for idx, (load, title) in enumerate(zip(comparison_loads, titles)):
    ax = axes[idx]
    phase_dir = f"{BASE_DIR}/load-{load}"

    df_decomp = parse_latency_decomp(f"{phase_dir}/latency_decomp.log")

    components = {}
    for col in ["T_network", "T_proxy_total"]:
        if col in df_decomp.columns and len(df_decomp[col].dropna()) > 0:
            values = df_decomp[col].dropna() / 1000.0  # ns → μs
            components[col] = {
                "p50": np.percentile(values, 50),
                "p99": np.percentile(values, 99),
                "p9999": np.percentile(values, 99.99) if len(values) > 100 else np.percentile(values, 99)
            }
        else:
            components[col] = {"p50": 0, "p99": 0, "p9999": 0}

    # Stacked bar for each percentile
    percentiles = ["P50", "P99", "P99.99"]
    pct_keys = ["p50", "p99", "p9999"]
    x = np.arange(len(percentiles))

    network_vals = [components.get("T_network", {}).get(k, 0) for k in pct_keys]
    proxy_vals = [components.get("T_proxy_total", {}).get(k, 0) for k in pct_keys]

    ax.bar(x, network_vals, 0.5, label="T_network", color=colors[0])
    ax.bar(x, proxy_vals, 0.5, bottom=network_vals, label="T_proxy_total", color=colors[2])

    ax.set_xlabel("Percentile")
    ax.set_xticks(x)
    ax.set_xticklabels(percentiles)
    ax.set_title(title)
    ax.legend()
    ax.grid(True, alpha=0.3, axis='y')

axes[0].set_ylabel("Latency (μs)")

plt.suptitle("Baseline vs. Interference: Latency Breakdown", fontsize=15, fontweight='bold')
plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/baseline_vs_interference.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/baseline_vs_interference.png", bbox_inches="tight")
plt.close()


# ================================================
# COMBINED FIGURE (All 8 plots in 4x2 grid — summary)
# ================================================
fig, axs = plt.subplots(2, 2, figsize=(16, 12))

# (a) Stacked Latency Breakdown
ax = axs[0, 0]
x = np.arange(len(LOAD_LEVELS))
net_p99, proxy_p99 = [], []
for load in LOAD_LEVELS:
    df = parse_latency_decomp(f"{BASE_DIR}/load-{load}/latency_decomp.log")
    if "T_network" in df.columns and len(df) > 0:
        net_p99.append(np.percentile(df["T_network"].dropna() / 1000.0, 99))
    else:
        net_p99.append(0)
    if "T_proxy_total" in df.columns and len(df) > 0:
        proxy_p99.append(np.percentile(df["T_proxy_total"].dropna() / 1000.0, 99))
    else:
        proxy_p99.append(0)

ax.bar(x, net_p99, 0.5, label="T_network", color=colors[0])
ax.bar(x, proxy_p99, 0.5, bottom=net_p99, label="T_proxy", color=colors[2])
ax.set_xticks(x)
ax.set_xticklabels([str(l) for l in LOAD_LEVELS])
ax.set_title("(a) Stacked Latency Breakdown")
ax.set_ylabel("P99 Latency (μs)")
ax.legend(fontsize=8)

# (b) Queue Delay vs Load
ax = axs[0, 1]
q_p99 = []
for load in LOAD_LEVELS:
    df = parse_queue_delay(f"{BASE_DIR}/load-{load}/queue_delay.log")
    if len(df) > 0:
        q_p99.append(np.percentile(df["delay_ns"] / 1000.0, 99))
    else:
        q_p99.append(0)
ax.plot(LOAD_LEVELS, q_p99, marker='o', color=colors[2], linewidth=2)
ax.set_title("(b) Queue Delay vs Load")
ax.set_xlabel("svc-B Load (RPS)")
ax.set_ylabel("Queue Delay P99 (μs)")

# (c) Queue Delay vs Execution (scatter)
ax = axs[1, 0]
for i, load in enumerate(LOAD_LEVELS):
    df_d = parse_latency_decomp(f"{BASE_DIR}/load-{load}/latency_decomp.log")
    df_q = parse_queue_delay(f"{BASE_DIR}/load-{load}/queue_delay.log")
    if "T_proxy_total" in df_d.columns and len(df_d) > 0 and len(df_q) > 0:
        n = min(len(df_d), len(df_q), 200)
        ax.scatter(df_d["T_proxy_total"].values[:n] / 1000.0,
                   df_q["delay_ns"].values[:n] / 1000.0,
                   alpha=0.3, s=10, color=colors[i], label=f"{load}")
ax.set_title("(c) Queue vs Execution")
ax.set_xlabel("T_proxy (μs)")
ax.set_ylabel("Queue Delay (μs)")
ax.legend(fontsize=8, title="svc-B RPS")

# (d) Baseline vs Interference bars
ax = axs[1, 1]
for j, load in enumerate([0, 1000]):
    df = parse_latency_decomp(f"{BASE_DIR}/load-{load}/latency_decomp.log")
    net_val = 0
    prx_val = 0
    if "T_network" in df.columns and len(df) > 0:
        net_val = np.percentile(df["T_network"].dropna() / 1000.0, 99)
    if "T_proxy_total" in df.columns and len(df) > 0:
        prx_val = np.percentile(df["T_proxy_total"].dropna() / 1000.0, 99)
    offset = j * 0.5
    ax.bar([offset], [net_val], 0.4, label=f"T_net ({load})" if j == 0 else "", color=colors[0])
    ax.bar([offset], [prx_val], 0.4, bottom=[net_val],
           label=f"T_proxy ({load})" if j == 0 else "", color=colors[2])
ax.set_xticks([0, 0.5])
ax.set_xticklabels(["Baseline\n(0 RPS)", "Interference\n(1000 RPS)"])
ax.set_title("(d) Baseline vs Interference")
ax.set_ylabel("P99 Latency (μs)")
ax.legend(fontsize=8)

plt.suptitle("Experiment 4: Latency Decomposition via eBPF — Summary", fontsize=16, fontweight='bold')
plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/combined_summary.pdf")
plt.savefig(f"{PLOTS_DIR}/combined_summary.png")
plt.close()


# ================================================
# INSIGHTS
# ================================================
print("\n===== EXPERIMENT 4 SUMMARY =====")
print("Baseline vs Interference (P99 latency components):")
for load in [0, 1000]:
    df = parse_latency_decomp(f"{BASE_DIR}/load-{load}/latency_decomp.log")
    net = np.percentile(df["T_network"].dropna() / 1000.0, 99) if "T_network" in df.columns and len(df) > 0 else 0
    prx = np.percentile(df["T_proxy_total"].dropna() / 1000.0, 99) if "T_proxy_total" in df.columns and len(df) > 0 else 0
    total = net + prx
    pct = prx / total * 100 if total > 0 else 0
    print(f"  svc-B={load:4d} RPS → T_net={net:.1f}μs, T_proxy={prx:.1f}μs ({pct:.1f}% from proxy)")

print(f"\n✅ Saved combined plots → {PLOTS_DIR}")
