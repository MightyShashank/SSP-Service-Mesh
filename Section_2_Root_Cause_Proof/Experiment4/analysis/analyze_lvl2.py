import argparse
import json
import os
import re

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

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
# ARGUMENTS
# -------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--run_id", required=True)
args = parser.parse_args()

BASE_DIR = f"results/raw/{args.run_id}"
PLOTS_DIR = f"results/plots_lvl2/{args.run_id}"
PROC_DIR = f"results/processed/{args.run_id}"

os.makedirs(PLOTS_DIR, exist_ok=True)
os.makedirs(PROC_DIR, exist_ok=True)

LOAD_LEVELS = [0, 100, 500, 1000]

# -------------------------------
# PARSE QUEUE DELAY LOGS
# Format: QUEUE|<tid>|<timestamp>|delay_ns=<value>
# -------------------------------
def parse_queue_delay(log_path):
    records = []

    if not os.path.exists(log_path):
        print(f"[WARN] Queue delay log not found: {log_path}")
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

            records.append({
                "tid": tid,
                "timestamp": ts,
                "delay_ns": delay_ns
            })

    return pd.DataFrame(records)


# -------------------------------
# PARSE SCHEDULER OCCUPANCY LOGS
# Extract final on-CPU and off-CPU totals per thread
# -------------------------------
def parse_sched_occupancy(log_path):
    """
    Parse the FINAL OCCUPANCY SUMMARY from sched_occupancy.bt output.
    Returns dict of tid → occupancy_pct.
    """
    oncpu = {}
    offcpu = {}

    if not os.path.exists(log_path):
        print(f"[WARN] Sched occupancy log not found: {log_path}")
        return {}

    with open(log_path) as f:
        content = f.read()

    # Parse @oncpu_total and @offcpu_total from bpftrace map output
    # bpftrace prints maps as: @map[key]: value
    in_oncpu = False
    in_offcpu = False

    for line in content.split("\n"):
        if "Total on-CPU time" in line:
            in_oncpu = True
            in_offcpu = False
            continue
        if "Total off-CPU time" in line:
            in_oncpu = False
            in_offcpu = True
            continue
        if "END" in line:
            break

        # Parse bpftrace map entries: @oncpu_total[12345]: 678900
        match = re.match(r'@\w+\[(\d+)\]:\s+(\d+)', line.strip())
        if match:
            tid = int(match.group(1))
            val = int(match.group(2))
            if in_oncpu:
                oncpu[tid] = val
            elif in_offcpu:
                offcpu[tid] = val

    # Compute occupancy per thread
    occupancy = {}
    all_tids = set(oncpu.keys()) | set(offcpu.keys())
    for tid in all_tids:
        on = oncpu.get(tid, 0)
        off = offcpu.get(tid, 0)
        total = on + off
        occupancy[tid] = (on / total * 100) if total > 0 else 0

    return occupancy


# -------------------------------
# LOAD & PROCESS DATA
# -------------------------------
queue_delays_by_load = {}
occupancy_by_load = {}

for load in LOAD_LEVELS:
    phase_dir = f"{BASE_DIR}/load-{load}"

    # Queue delay
    df_queue = parse_queue_delay(f"{phase_dir}/queue_delay.log")
    if len(df_queue) > 0:
        delays_us = df_queue["delay_ns"] / 1000.0  # ns → μs
        queue_delays_by_load[load] = {
            "p50": np.percentile(delays_us, 50),
            "p99": np.percentile(delays_us, 99),
            "p9999": np.percentile(delays_us, 99.99) if len(delays_us) > 100 else np.percentile(delays_us, 99),
            "mean": np.mean(delays_us),
            "count": len(delays_us),
            "raw_us": delays_us.tolist()
        }
    else:
        queue_delays_by_load[load] = {"p50": 0, "p99": 0, "p9999": 0, "mean": 0, "count": 0, "raw_us": []}

    # Occupancy
    occ = parse_sched_occupancy(f"{phase_dir}/sched_occupancy.log")
    if occ:
        avg_occ = np.mean(list(occ.values()))
        occupancy_by_load[load] = {
            "avg_pct": avg_occ,
            "per_thread": occ
        }
    else:
        occupancy_by_load[load] = {"avg_pct": 0, "per_thread": {}}


# Save processed data
save_data = {
    "queue_delays": {str(k): {kk: vv for kk, vv in v.items() if kk != "raw_us"}
                     for k, v in queue_delays_by_load.items()},
    "occupancy": {str(k): {"avg_pct": v["avg_pct"]}
                  for k, v in occupancy_by_load.items()}
}
with open(f"{PROC_DIR}/queue_and_occupancy.json", "w") as f:
    json.dump(save_data, f, indent=2, default=float)


# ================================================
# PLOT 3: Proxy Queue Delay vs. svc-B Load
# ================================================
fig, ax = plt.subplots(figsize=(8, 5))

loads_plot = []
p9999_vals = []
p99_vals = []
p50_vals = []

for load in LOAD_LEVELS:
    d = queue_delays_by_load.get(load, {})
    loads_plot.append(load)
    p9999_vals.append(d.get("p9999", 0))
    p99_vals.append(d.get("p99", 0))
    p50_vals.append(d.get("p50", 0))

ax.plot(loads_plot, p9999_vals, marker='o', label="P99.99", color=colors[2], linewidth=2.5)
ax.plot(loads_plot, p99_vals, marker='s', label="P99", color=colors[1], linewidth=2)
ax.plot(loads_plot, p50_vals, marker='^', label="P50", color=colors[0], linewidth=1.5)

ax.set_xlabel("svc-B Load (RPS)")
ax.set_ylabel("Proxy Queue Delay (μs)")
ax.set_title("Proxy Queue Delay vs. svc-B Load")
ax.legend()
ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/queue_delay_vs_load.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/queue_delay_vs_load.png", bbox_inches="tight")
plt.close()


# ================================================
# PLOT 4: Worker Occupancy vs. Queue Delay (Correlation)
# ================================================
fig, ax1 = plt.subplots(figsize=(10, 6))

# Dual-axis plot
occ_vals = [occupancy_by_load.get(l, {}).get("avg_pct", 0) for l in LOAD_LEVELS]
queue_vals = [queue_delays_by_load.get(l, {}).get("p99", 0) for l in LOAD_LEVELS]

color1 = colors[3]
color2 = colors[2]

ax1.set_xlabel("svc-B Load (RPS)")
ax1.set_ylabel("Worker Occupancy (%)", color=color1)
ax1.bar(np.arange(len(LOAD_LEVELS)) - 0.15, occ_vals, 0.3,
        label="Worker Occupancy", color=color1, alpha=0.7)
ax1.tick_params(axis='y', labelcolor=color1)
ax1.set_xticks(np.arange(len(LOAD_LEVELS)))
ax1.set_xticklabels([str(l) for l in LOAD_LEVELS])

ax2 = ax1.twinx()
ax2.set_ylabel("Queue Delay P99 (μs)", color=color2)
ax2.plot(np.arange(len(LOAD_LEVELS)), queue_vals,
         marker='o', color=color2, linewidth=2.5, label="Queue Delay P99")
ax2.tick_params(axis='y', labelcolor=color2)

# Combine legends
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper left")

ax1.set_title("Worker Occupancy vs. Queue Delay Correlation")

# Add correlation coefficient if we have enough data
if len([v for v in occ_vals if v > 0]) >= 3 and len([v for v in queue_vals if v > 0]) >= 3:
    r, p_val = stats.pearsonr(occ_vals, queue_vals)
    ax1.text(0.05, 0.95, f"r = {r:.3f}, p = {p_val:.4f}",
             transform=ax1.transAxes, fontsize=11,
             verticalalignment='top',
             bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/occupancy_vs_queue_delay.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/occupancy_vs_queue_delay.png", bbox_inches="tight")
plt.close()


# ================================================
# INSIGHTS
# ================================================
print("\n===== QUEUE DELAY & OCCUPANCY INSIGHTS =====")
for load in LOAD_LEVELS:
    d = queue_delays_by_load.get(load, {})
    o = occupancy_by_load.get(load, {})
    print(f"  svc-B={load:4d} RPS → Queue P99={d.get('p99', 0):.1f}μs, "
          f"P99.99={d.get('p9999', 0):.1f}μs, "
          f"Occupancy={o.get('avg_pct', 0):.1f}%")

print(f"\n✅ Saved plots → {PLOTS_DIR}")
print(f"✅ Saved metrics → {PROC_DIR}")
