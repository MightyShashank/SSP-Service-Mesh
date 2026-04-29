import argparse
import json
import os

import matplotlib.pyplot as plt
import numpy as np

# -------------------------------
# STYLE
# -------------------------------
plt.style.use("seaborn-v0_8-darkgrid")

plt.rcParams.update({
    "font.size": 12,
    "axes.titlesize": 14,
    "axes.labelsize": 12,
    "legend.fontsize": 10,
    "figure.figsize": (6, 4),
    "savefig.dpi": 300,
    "lines.linewidth": 2
})

colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd"]

# -------------------------------
# ARGUMENTS
# -------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--run_id", required=True)
args = parser.parse_args()

BASE_DIR = f"results/raw/{args.run_id}"
PLOTS_DIR = f"results/plots_lvl2/{args.run_id}"

os.makedirs(PLOTS_DIR, exist_ok=True)

# -------------------------------
# LOAD JSON
# -------------------------------
def load_json(path):
    with open(path) as f:
        return json.load(f)

def extract(data):
    hist = data["DurationHistogram"]

    def get(p):
        for x in hist["Percentiles"]:
            if x["Percentile"] == p:
                return x["Value"]
        return None

    return {
        "p50": get(50),
        "p90": get(90),
        "p99": get(99),
        "p999": get(99.9),
        "qps": data["ActualQPS"],
        "count": hist["Count"]
    }

def get_cdf(data):
    hist = data["DurationHistogram"]["Data"]
    total = data["DurationHistogram"]["Count"]
    xs, ys, cum = [], [], 0

    for b in hist:
        cum += b["Count"]
        xs.append(b["End"])
        ys.append(cum / total)

    return xs, ys

# -------------------------------
# LOAD DATA
# -------------------------------
baseline_raw = load_json(f"{BASE_DIR}/baseline/baseline.json")
interf_raw = load_json(f"{BASE_DIR}/interference/svc-a.json")

baseline = extract(baseline_raw)

loads = [500, 1000, 2000, 4000]

svc_a_ramp, svc_a_raw = [], []
svc_b_ramp, svc_b_raw = [], []

for l in loads:
    raw_a = load_json(f"{BASE_DIR}/load-ramp/svc-a_{l}.json")
    svc_a_raw.append(raw_a)
    svc_a_ramp.append(extract(raw_a))

    path_b = f"{BASE_DIR}/load-ramp/svc-b_{l}.json"
    if os.path.exists(path_b):
        raw_b = load_json(path_b)
        svc_b_raw.append(raw_b)
        svc_b_ramp.append(extract(raw_b))
    else:
        svc_b_ramp.append(None)

# -------------------------------
# 1. Percentiles vs Load
# -------------------------------
plt.figure()

for i, label in enumerate(["p50", "p90", "p99", "p999"]):
    plt.plot(loads,
             [m[label] for m in svc_a_ramp],
             marker='o',
             label=label.upper(),
             color=colors[i])

plt.xlabel("Load (QPS)")
plt.ylabel("Latency (s)")
plt.title("Latency Percentiles vs Load")
plt.legend()
plt.grid()

plt.savefig(f"{PLOTS_DIR}/percentiles_vs_load.pdf", bbox_inches="tight")
plt.close()

# -------------------------------
# 2. CDF Multi
# -------------------------------
plt.figure()

x, y = get_cdf(baseline_raw)
plt.plot(x, y, label="baseline", color=colors[0])

x, y = get_cdf(interf_raw)
plt.plot(x, y, label="interference", color=colors[1])

for i, l in enumerate(loads):
    x, y = get_cdf(svc_a_raw[i])
    plt.plot(x, y, label=f"load={l}", color=colors[i+1])

plt.xlabel("Latency (s)")
plt.ylabel("CDF")
plt.title("Latency Distribution")
plt.legend()
plt.grid()

plt.savefig(f"{PLOTS_DIR}/cdf_multi.pdf", bbox_inches="tight")
plt.close()

# -------------------------------
# 3. Load vs Latency
# -------------------------------
plt.figure()

plt.plot(loads,
         [m["p99"] for m in svc_a_ramp],
         marker='o',
         label="svc-a",
         color=colors[0])

if svc_b_ramp[0]:
    plt.plot(loads,
             [m["p99"] for m in svc_b_ramp],
             marker='o',
             label="svc-b",
             color=colors[1])

plt.xlabel("Offered Load (QPS)")
plt.ylabel("P99 Latency")
plt.title("Load vs Latency")
plt.legend()
plt.grid()

plt.savefig(f"{PLOTS_DIR}/load_vs_latency_multi.pdf", bbox_inches="tight")
plt.close()

# -------------------------------
# 4. Tail Amplification
# -------------------------------
plt.figure()

baseline_p99_a = baseline["p99"]

plt.plot(loads,
         [m["p99"]/baseline_p99_a for m in svc_a_ramp],
         marker='o',
         label="svc-a",
         color=colors[0])

if svc_b_ramp[0]:
    plt.plot(loads,
             [m["p99"]/baseline_p99_a for m in svc_b_ramp],
             marker='o',
             label="svc-b",
             color=colors[1])

plt.xlabel("Load")
plt.ylabel("P99 Amplification")
plt.title("Tail Amplification")
plt.legend()
plt.grid()

plt.savefig(f"{PLOTS_DIR}/tail_amp_multi.pdf", bbox_inches="tight")
plt.close()

# -------------------------------
# 5. Combined Figure
# -------------------------------
fig, axs = plt.subplots(2, 2, figsize=(10, 8))

# (a) Percentiles
for i, label in enumerate(["p50", "p90", "p99"]):
    axs[0, 0].plot(loads,
                   [m[label] for m in svc_a_ramp],
                   marker='o',
                   label=label.upper(),
                   color=colors[i])
axs[0, 0].set_title("(a) Percentiles")
axs[0, 0].legend()

# (b) CDF
for label, raw, c in [
    ("baseline", baseline_raw, colors[0]),
    ("interference", interf_raw, colors[1])
]:
    x, y = get_cdf(raw)
    axs[0, 1].plot(x, y, label=label, color=c)
axs[0, 1].set_title("(b) CDF")
axs[0, 1].legend()

# (c) Load vs Latency
axs[1, 0].plot(loads,
               [m["p99"] for m in svc_a_ramp],
               marker='o',
               label="svc-a",
               color=colors[0])
if svc_b_ramp[0]:
    axs[1, 0].plot(loads,
                   [m["p99"] for m in svc_b_ramp],
                   marker='o',
                   label="svc-b",
                   color=colors[1])
axs[1, 0].set_title("(c) Load vs Latency")
axs[1, 0].legend()

# (d) Tail Amplification
axs[1, 1].plot(loads,
               [m["p99"]/baseline_p99_a for m in svc_a_ramp],
               marker='o',
               label="svc-a",
               color=colors[0])
if svc_b_ramp[0]:
    axs[1, 1].plot(loads,
                   [m["p99"]/baseline_p99_a for m in svc_b_ramp],
                   marker='o',
                   label="svc-b",
                   color=colors[1])
axs[1, 1].set_title("(d) Tail Amplification")
axs[1, 1].legend()

plt.tight_layout()
plt.savefig(f"{PLOTS_DIR}/combined_figure.pdf")
plt.close()

print("\n✅ FINAL polished plots generated at:", PLOTS_DIR)