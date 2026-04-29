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
    "figure.figsize": (8, 5),
    "savefig.dpi": 300,
    "lines.linewidth": 2
})

colors = ["#2ca02c", "#ff7f0e", "#d62728", "#1f77b4", "#9467bd"]

# -------------------------------
# ARGUMENT PARSING
# -------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--run_id", required=True)
args = parser.parse_args()

BASE_DIR = f"results/raw/{args.run_id}"
PLOTS_DIR = f"results/plots_lvl1/{args.run_id}"
PROC_DIR = f"results/processed/{args.run_id}"

os.makedirs(PLOTS_DIR, exist_ok=True)
os.makedirs(PROC_DIR, exist_ok=True)

LOAD_LEVELS = [0, 100, 500, 1000]

# -------------------------------
# PARSE EBPF LATENCY DECOMPOSITION LOGS
# -------------------------------
def parse_latency_decomp(log_path):
    """
    Parse latency_decomp.bt output for DECOMP lines.
    Format: DECOMP|<tid>|<timestamp>|t1=...|t2=...|T_network=...
    """
    records = []

    if not os.path.exists(log_path):
        print(f"[WARN] Latency decomp log not found: {log_path}")
        return pd.DataFrame()

    with open(log_path) as f:
        for line in f:
            if not line.startswith("DECOMP|"):
                continue

            parts = line.strip().split("|")
            if len(parts) < 4:
                continue

            record = {
                "tid": int(parts[1]),
                "timestamp": int(parts[2])
            }

            for kv in parts[3:]:
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    try:
                        record[k] = int(v)
                    except ValueError:
                        record[k] = v

            records.append(record)

    return pd.DataFrame(records)


def compute_latency_components(df):
    """
    Compute latency component statistics from parsed DECOMP records.
    Returns dict with median, p99, p99.99 for each component (in microseconds).
    """
    result = {}

    for col in ["T_network", "T_proxy_total"]:
        if col in df.columns:
            values = df[col].dropna() / 1000.0  # ns → μs
            result[col] = {
                "p50": np.percentile(values, 50) if len(values) > 0 else 0,
                "p99": np.percentile(values, 99) if len(values) > 0 else 0,
                "p9999": np.percentile(values, 99.99) if len(values) > 0 else 0,
                "count": len(values)
            }

    return result


# -------------------------------
# LOAD & PROCESS DATA
# -------------------------------
all_components = {}

for load in LOAD_LEVELS:
    phase_dir = f"{BASE_DIR}/load-{load}"
    log_path = f"{phase_dir}/latency_decomp.log"

    df = parse_latency_decomp(log_path)
    components = compute_latency_components(df)
    all_components[load] = components

# Save processed metrics
with open(f"{PROC_DIR}/latency_components.json", "w") as f:
    # Convert numpy values to float for JSON serialization
    serializable = {}
    for load, comps in all_components.items():
        serializable[str(load)] = {}
        for name, stats in comps.items():
            serializable[str(load)][name] = {k: float(v) for k, v in stats.items()}
    json.dump(serializable, f, indent=2)


# ================================================
# PLOT 1: Stacked Latency Breakdown vs. Load
# ================================================
fig, ax = plt.subplots(figsize=(10, 6))

x = np.arange(len(LOAD_LEVELS))
width = 0.5

network_p99 = []
proxy_p99 = []

for load in LOAD_LEVELS:
    comps = all_components.get(load, {})
    network_p99.append(comps.get("T_network", {}).get("p99", 0))
    proxy_p99.append(comps.get("T_proxy_total", {}).get("p99", 0))

bar1 = ax.bar(x, network_p99, width, label="T_network", color=colors[0])
bar2 = ax.bar(x, proxy_p99, width, bottom=network_p99, label="T_proxy_total", color=colors[2])

ax.set_xlabel("svc-B Load (RPS)")
ax.set_ylabel("P99 Latency (μs)")
ax.set_title("Stacked Latency Breakdown vs. svc-B Load")
ax.set_xticks(x)
ax.set_xticklabels([str(l) for l in LOAD_LEVELS])
ax.legend()

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/stacked_latency_breakdown.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/stacked_latency_breakdown.png", bbox_inches="tight")
plt.close()


# ================================================
# PLOT 2: Latency Component Distributions (Histograms)
# ================================================
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

for idx, component in enumerate(["T_network", "T_proxy_total"]):
    ax = axes[idx]

    for i, load in enumerate(LOAD_LEVELS):
        phase_dir = f"{BASE_DIR}/load-{load}"
        log_path = f"{phase_dir}/latency_decomp.log"
        df = parse_latency_decomp(log_path)

        if component in df.columns and len(df[component].dropna()) > 0:
            values = df[component].dropna() / 1000.0  # ns → μs
            ax.hist(values, bins=50, alpha=0.6,
                    label=f"svc-B={load} RPS",
                    color=colors[i % len(colors)])

    ax.set_xlabel("Latency (μs)")
    ax.set_ylabel("Count")
    ax.set_title(f"{component} Distribution")
    ax.set_yscale("log")
    ax.legend()
    ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/component_histograms.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/component_histograms.png", bbox_inches="tight")
plt.close()


# ================================================
# INSIGHTS
# ================================================
print("\n===== LATENCY DECOMPOSITION INSIGHTS =====")
for load in LOAD_LEVELS:
    comps = all_components.get(load, {})
    net = comps.get("T_network", {}).get("p99", 0)
    proxy = comps.get("T_proxy_total", {}).get("p99", 0)
    total = net + proxy
    pct = (proxy / total * 100) if total > 0 else 0

    print(f"  svc-B={load:4d} RPS → T_network={net:.1f}μs, T_proxy={proxy:.1f}μs "
          f"({pct:.1f}% from proxy)")

print(f"\nSaved plots → {PLOTS_DIR}")
print(f"Saved metrics → {PROC_DIR}")
