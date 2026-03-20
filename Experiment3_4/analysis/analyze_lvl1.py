import argparse
import json
import os

import matplotlib.pyplot as plt
import numpy as np

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

# -------------------------------
# LOAD JSON
# -------------------------------
def load_json(path):
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    with open(path) as f:
        return json.load(f)

# -------------------------------
# METRIC EXTRACTION (FIXED)
# -------------------------------
def extract_metrics(data, label="unknown"):
    try:
        hist = data["DurationHistogram"]
        percentiles = hist["Percentiles"]

        def get_p(p):
            for item in percentiles:
                if item["Percentile"] == p:
                    return item["Value"]
            return None

        num = data["NumRequests"]
        duration = data["ActualDuration"]  # already seconds

        avg = duration / num

        return {
            "avg": avg,
            "p50": get_p(50),
            "p90": get_p(90),
            "p99": get_p(99),
            "p999": get_p(99.9),
            "qps": data["ActualQPS"],
            "count": num
        }

    except Exception as e:
        print(f"[WARN] {label} failed: {e}")
        return None

# -------------------------------
# ADVANCED METRICS
# -------------------------------
def tail_amplification(base, curr):
    return curr["p99"] / base["p99"]

def slowdown(base, curr):
    return curr["avg"] / base["avg"]

def tail_slope(p90, p99):
    return (p99 - p90) / p90

# -------------------------------
# CDF (FIXED)
# -------------------------------
def compute_cdf(data):
    buckets = data["DurationHistogram"]["Buckets"]
    total = data["NumRequests"]

    xs, ys = [], []
    cumsum = 0

    for b in buckets:
        cumsum += b["Count"]
        xs.append(b["UpperBound"])
        ys.append(cumsum / total)

    return xs, ys

# -------------------------------
# LOAD DATA
# -------------------------------
baseline_raw = load_json(f"{BASE_DIR}/baseline/baseline.json")
interf_raw = load_json(f"{BASE_DIR}/interference/svc-a.json")

baseline = extract_metrics(baseline_raw, "baseline")
interf = extract_metrics(interf_raw, "interference")

loads = [500, 1000, 2000, 4000]
ramp = []

for l in loads:
    raw = load_json(f"{BASE_DIR}/load-ramp/svc-a_{l}.json")
    ramp.append(extract_metrics(raw, f"ramp-{l}"))

# -------------------------------
# ADVANCED ANALYSIS
# -------------------------------
slow = slowdown(baseline, interf)
tail = tail_amplification(baseline, interf)
slope = tail_slope(interf["p90"], interf["p99"])

print("\n===== INSIGHTS =====")
print(f"Slowdown: {slow:.2f}x")
print(f"P99 Amplification: {tail:.2f}x")
print(f"Tail slope: {slope:.2f}")

# -------------------------------
# SAVE METRICS
# -------------------------------
with open(f"{PROC_DIR}/metrics.json", "w") as f:
    json.dump({
        "baseline": baseline,
        "interference": interf,
        "slowdown": slow,
        "tail_amplification": tail,
        "tail_slope": slope
    }, f, indent=2)

# -------------------------------
# PLOT 1 — LATENCY COMPARISON
# -------------------------------
labels = ["P50", "P90", "P99", "P99.9"]

b_vals = [baseline["p50"], baseline["p90"], baseline["p99"], baseline["p999"]]
i_vals = [interf["p50"], interf["p90"], interf["p99"], interf["p999"]]

x = np.arange(len(labels))

plt.figure()
plt.bar(x - 0.2, b_vals, 0.4, label="Baseline")
plt.bar(x + 0.2, i_vals, 0.4, label="Interference")
plt.xticks(x, labels)
plt.ylabel("Latency (s)")
plt.title("Baseline vs Interference")
plt.legend()
plt.savefig(f"{PLOTS_DIR}/latency_compare.png")
plt.close()

# -------------------------------
# PLOT 2 — LOAD VS LATENCY
# -------------------------------
p99_vals = [m["p99"] for m in ramp]

plt.figure()
plt.plot(loads, p99_vals, marker="o")
plt.xlabel("Load on svc-b (QPS)")
plt.ylabel("P99 latency (s)")
plt.title("Load vs Latency")
plt.grid()
plt.savefig(f"{PLOTS_DIR}/load_vs_latency.png")
plt.close()

# -------------------------------
# PLOT 3 — AMPLIFICATION CURVE
# -------------------------------
amp = [m["p99"] / baseline["p99"] for m in ramp]

plt.figure()
plt.plot(loads, amp, marker="o")
plt.xlabel("Load on svc-b")
plt.ylabel("Amplification")
plt.title("Tail Amplification")
plt.grid()
plt.savefig(f"{PLOTS_DIR}/amplification.png")
plt.close()

# -------------------------------
# PLOT 4 — CDF
# -------------------------------
x1, y1 = compute_cdf(baseline_raw)
x2, y2 = compute_cdf(interf_raw)

plt.figure()
plt.plot(x1, y1, label="Baseline")
plt.plot(x2, y2, label="Interference")
plt.xlabel("Latency (s)")
plt.ylabel("CDF")
plt.title("Latency Distribution")
plt.legend()
plt.grid()
plt.savefig(f"{PLOTS_DIR}/cdf.png")
plt.close()

print("\nSaved plots →", PLOTS_DIR)
print("Saved metrics →", PROC_DIR)