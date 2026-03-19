import argparse
import json
import os

import matplotlib.pyplot as plt
import numpy as np

# -------------------------------
# ARGUMENT PARSING
# -------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--run_id", required=True, help="Run ID inside results/raw/")
args = parser.parse_args()

BASE_DIR = f"results/raw/{args.run_id}"
PLOTS_DIR = f"results/plots/{args.run_id}"
PROC_DIR = f"results/processed/{args.run_id}"

os.makedirs(PLOTS_DIR, exist_ok=True)
os.makedirs(PROC_DIR, exist_ok=True)

# -------------------------------
# SAFE JSON LOADER
# -------------------------------
def load_json(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing file: {path}")
    with open(path) as f:
        return json.load(f)

# -------------------------------
# SAFE METRIC EXTRACTION
# -------------------------------
def extract_metrics(data, label="unknown"):
    try:
        hist = data.get("DurationHistogram", {})

        percentiles = hist.get("Percentiles", [])
        def get_percentile(p):
            for item in percentiles:
                if item.get("Percentile") == p:
                    return item.get("Value")
            return None

        num_requests = hist.get("Count", 0)
        duration_ns = data.get("ActualDuration", 0)

        if num_requests == 0:
            raise ValueError(f"No requests found in {label}")

        duration_sec = duration_ns / 1e9

        avg_latency = duration_sec / num_requests

        return {
            "avg": avg_latency,
            "p50": get_percentile(50),
            "p75": get_percentile(75),
            "p90": get_percentile(90),
            "p99": get_percentile(99),
            "p999": get_percentile(99.9),
            "qps": data.get("ActualQPS", 0),
            "count": num_requests
        }

    except Exception as e:
        print(f"[WARNING] Failed to parse {label}: {e}")
        return None

# -------------------------------
# ADVANCED METRICS
# -------------------------------
def compute_tail_slope(p90, p99):
    if p90 and p99 and p90 > 0:
        return (p99 - p90) / p90
    return None

def compute_jitter(data):
    hist = data.get("DurationHistogram", {})
    return hist.get("StdDev", None)

def compute_degradation(baseline, current):
    if baseline["p99"] and current["p99"]:
        return current["p99"] / baseline["p99"]
    return None

# -------------------------------
# LOAD DATA
# -------------------------------
baseline_raw = load_json(f"{BASE_DIR}/baseline/baseline.json")
interf_raw = load_json(f"{BASE_DIR}/interference/svc-a.json")

baseline = extract_metrics(baseline_raw, "baseline")
svc_a_interf = extract_metrics(interf_raw, "interference")

# load ramp
loads = [500, 1000, 2000, 4000]
svc_a_ramp = []
svc_a_ramp_raw = []

for l in loads:
    path = f"{BASE_DIR}/load-ramp/svc-a_{l}.json"
    raw = load_json(path)
    svc_a_ramp_raw.append(raw)
    svc_a_ramp.append(extract_metrics(raw, f"svc-a_{l}"))

# -------------------------------
# ADVANCED ANALYSIS
# -------------------------------
slowdown = svc_a_interf["avg"] / baseline["avg"]
tail_amp = svc_a_interf["p99"] / baseline["p99"]

tail_slope = compute_tail_slope(svc_a_interf["p90"], svc_a_interf["p99"])
jitter = compute_jitter(interf_raw)

degradation_curve = [
    compute_degradation(baseline, m) for m in svc_a_ramp
]

print("\n===== KEY INSIGHTS =====")
print(f"Avg slowdown: {slowdown:.2f}x")
print(f"P99 amplification: {tail_amp:.2f}x")
print(f"Tail slope (P99 vs P90): {tail_slope:.2f}")
print(f"Jitter (StdDev): {jitter:.4f}")

# -------------------------------
# SAVE PROCESSED METRICS
# -------------------------------
processed = {
    "baseline": baseline,
    "interference": svc_a_interf,
    "load_ramp": dict(zip(loads, svc_a_ramp)),
    "advanced": {
        "slowdown": slowdown,
        "tail_amplification": tail_amp,
        "tail_slope": tail_slope,
        "jitter": jitter,
        "degradation_curve": dict(zip(loads, degradation_curve))
    }
}

with open(f"{PROC_DIR}/metrics.json", "w") as f:
    json.dump(processed, f, indent=2)

# -------------------------------
# PLOT 1 — BASELINE VS INTERFERENCE
# -------------------------------
labels = ["P50", "P90", "P99", "P99.9"]

baseline_vals = [
    baseline["p50"], baseline["p90"],
    baseline["p99"], baseline["p999"]
]

interf_vals = [
    svc_a_interf["p50"], svc_a_interf["p90"],
    svc_a_interf["p99"], svc_a_interf["p999"]
]

x = np.arange(len(labels))
width = 0.35

plt.figure()
plt.bar(x - width/2, baseline_vals, width, label="Baseline")
plt.bar(x + width/2, interf_vals, width, label="Interference")
plt.xticks(x, labels)
plt.ylabel("Latency (s)")
plt.title("Latency Comparison")
plt.legend()

plt.savefig(f"{PLOTS_DIR}/baseline_vs_interference.png")
plt.close()

# -------------------------------
# PLOT 2 — LOAD VS LATENCY
# -------------------------------
p99_vals = [m["p99"] for m in svc_a_ramp]

plt.figure()
plt.plot(loads, p99_vals, marker='o')
plt.xlabel("Load on svc-b (QPS)")
plt.ylabel("P99 Latency (s)")
plt.title("Load vs Latency (svc-a)")
plt.grid()

plt.savefig(f"{PLOTS_DIR}/load_vs_latency.png")
plt.close()

# -------------------------------
# PLOT 3 — TAIL AMPLIFICATION
# -------------------------------
plt.figure()
plt.plot(loads, degradation_curve, marker='o')
plt.xlabel("Load on svc-b")
plt.ylabel("P99 Amplification")
plt.title("Tail Latency Amplification")
plt.grid()

plt.savefig(f"{PLOTS_DIR}/tail_amplification.png")
plt.close()

# -------------------------------
# PLOT 4 — CDF
# -------------------------------
def plot_cdf(data):
    hist = data["DurationHistogram"]["Data"]
    xs = []
    ys = []

    total = data["DurationHistogram"]["Count"]
    cumulative = 0

    for b in hist:
        cumulative += b["Count"]
        xs.append(b["End"])
        ys.append(cumulative / total)

    return xs, ys

x1, y1 = plot_cdf(baseline_raw)
x2, y2 = plot_cdf(interf_raw)

plt.figure()
plt.plot(x1, y1, label="Baseline")
plt.plot(x2, y2, label="Interference")
plt.xlabel("Latency (s)")
plt.ylabel("CDF")
plt.title("Latency Distribution (CDF)")
plt.legend()
plt.grid()

plt.savefig(f"{PLOTS_DIR}/cdf.png")
plt.close()

print("\nPlots saved to:", PLOTS_DIR)
print("Processed metrics saved to:", PROC_DIR)