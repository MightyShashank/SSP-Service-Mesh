import argparse
import json
import os
import re

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
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
PLOTS_DIR = f"results/plots_lvl3/{args.run_id}"
PROC_DIR = f"results/processed/{args.run_id}"

os.makedirs(PLOTS_DIR, exist_ok=True)
os.makedirs(PROC_DIR, exist_ok=True)

LOAD_LEVELS = [0, 100, 500, 1000]

# -------------------------------
# PARSE HELPERS
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


def load_fortio_json(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)


def extract_fortio_metrics(data):
    if data is None:
        return None
    try:
        hist = data["DurationHistogram"]
        percentiles = hist["Percentiles"]

        def get_p(p):
            for item in percentiles:
                if item["Percentile"] == p:
                    return item["Value"]
            return None

        return {
            "p50": get_p(50),
            "p90": get_p(90),
            "p99": get_p(99),
            "p999": get_p(99.9),
            "qps": data["ActualQPS"]
        }
    except Exception:
        return None


# ================================================
# PLOT 5: CPU Utilization vs. End-to-End Latency
# (CPU–Latency Decoupling Plot)
# ================================================

# Load system metrics and Fortio data per load level
cpu_pcts = []
e2e_p9999 = []

for load in LOAD_LEVELS:
    phase_dir = f"{BASE_DIR}/load-{load}"

    # Estimate CPU from sched occupancy (proxy-level) or system metrics
    occ_log = f"{phase_dir}/sched_occupancy.log"
    occ_pct = 0
    if os.path.exists(occ_log):
        oncpu = {}
        offcpu = {}
        in_on = False
        in_off = False
        with open(occ_log) as f:
            for line in f:
                if "Total on-CPU time" in line:
                    in_on, in_off = True, False
                    continue
                if "Total off-CPU time" in line:
                    in_on, in_off = False, True
                    continue
                if "END" in line:
                    break
                match = re.match(r'@\w+\[(\d+)\]:\s+(\d+)', line.strip())
                if match:
                    t, v = int(match.group(1)), int(match.group(2))
                    if in_on:
                        oncpu[t] = v
                    elif in_off:
                        offcpu[t] = v

        total_on = sum(oncpu.values())
        total_off = sum(offcpu.values())
        if total_on + total_off > 0:
            occ_pct = total_on / (total_on + total_off) * 100

    cpu_pcts.append(occ_pct)

    # E2E latency from Fortio
    fortio_data = load_fortio_json(f"{phase_dir}/svc-a.json")
    metrics = extract_fortio_metrics(fortio_data)
    if metrics and metrics.get("p999"):
        e2e_p9999.append(metrics["p999"] * 1000)  # s → ms
    else:
        e2e_p9999.append(0)


fig, ax1 = plt.subplots(figsize=(10, 6))

ax1.set_xlabel("svc-B Load (RPS)")

color1 = colors[3]
ax1.set_ylabel("ztunnel CPU Occupancy (%)", color=color1)
ax1.plot(LOAD_LEVELS, cpu_pcts, marker='s', color=color1, linewidth=2, label="CPU Occupancy")
ax1.tick_params(axis='y', labelcolor=color1)

ax2 = ax1.twinx()
color2 = colors[2]
ax2.set_ylabel("P99.9 Latency (ms)", color=color2)
ax2.plot(LOAD_LEVELS, e2e_p9999, marker='o', color=color2, linewidth=2.5, label="P99.9 Latency")
ax2.tick_params(axis='y', labelcolor=color2)

# Combine legends
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper left")

ax1.set_title("CPU Utilization vs. End-to-End Latency (Decoupling)")

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/cpu_vs_latency.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/cpu_vs_latency.png", bbox_inches="tight")
plt.close()


# ================================================
# PLOT 6: Head-of-Line Blocking Timeline
# (Per-request timeline of enqueue/dequeue events)
# ================================================
fig, ax = plt.subplots(figsize=(14, 6))

# Use the highest-load data for HoL visualization
hol_load = 1000
phase_dir = f"{BASE_DIR}/load-{hol_load}"
df_queue = parse_queue_delay(f"{phase_dir}/queue_delay.log")

if len(df_queue) > 0:
    # Take first 100 events for readability
    df_sample = df_queue.head(100).copy()
    df_sample["delay_us"] = df_sample["delay_ns"] / 1000.0

    # Normalize timestamps to start from 0
    t0 = df_sample["timestamp"].min()
    df_sample["t_rel_ms"] = (df_sample["timestamp"] - t0) / 1e6  # ns → ms

    # Assign unique TIDs to y-axis positions
    unique_tids = df_sample["tid"].unique()
    tid_to_y = {tid: i for i, tid in enumerate(unique_tids)}
    df_sample["y"] = df_sample["tid"].map(tid_to_y)

    # Draw request timelines as horizontal bars
    # Start of bar = wakeup time, width = scheduling delay
    for _, row in df_sample.iterrows():
        color = colors[2] if row["delay_us"] > 500 else colors[0]  # Red for high delay
        ax.barh(row["y"], row["delay_us"], left=row["t_rel_ms"],
                height=0.6, color=color, alpha=0.7, edgecolor='none')

    ax.set_xlabel("Time (ms from experiment start)")
    ax.set_ylabel("Worker Thread")
    ax.set_yticks(range(len(unique_tids)))
    ax.set_yticklabels([f"TID {tid}" for tid in unique_tids])

    # Legend
    green_patch = mpatches.Patch(color=colors[0], alpha=0.7, label="Normal delay (<500μs)")
    red_patch = mpatches.Patch(color=colors[2], alpha=0.7, label="High delay (>500μs, HoL blocking)")
    ax.legend(handles=[green_patch, red_patch], loc="upper right")
else:
    ax.text(0.5, 0.5, "No queue delay data available for HoL visualization",
            ha='center', va='center', transform=ax.transAxes, fontsize=14)

ax.set_title(f"Head-of-Line Blocking Timeline (svc-B = {hol_load} RPS)")
ax.grid(True, alpha=0.3, axis='x')

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/hol_blocking_timeline.pdf", bbox_inches="tight")
plt.savefig(f"{PLOTS_DIR}/hol_blocking_timeline.png", bbox_inches="tight")
plt.close()


# ================================================
# INSIGHTS
# ================================================
print("\n===== CPU-LATENCY & HOL BLOCKING INSIGHTS =====")
for i, load in enumerate(LOAD_LEVELS):
    print(f"  svc-B={load:4d} RPS → CPU={cpu_pcts[i]:.1f}%, P99.9={e2e_p9999[i]:.2f}ms")

if len(df_queue) > 0:
    high_delay = df_queue[df_queue["delay_ns"] > 500000]  # >500μs
    print(f"\n  HoL events (>500μs delay) at {hol_load} RPS: {len(high_delay)} / {len(df_queue)} "
          f"({len(high_delay)/len(df_queue)*100:.1f}%)")

print(f"\n✅ Saved plots → {PLOTS_DIR}")
