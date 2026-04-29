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
    "figure.figsize": (6, 4),
    "savefig.dpi": 300
})

# -------------------------------
# ARGUMENTS
# -------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--run_id", required=True)
args = parser.parse_args()

BASE = f"results/raw/{args.run_id}"
PLOTS = f"results/plots_lvl3/{args.run_id}"
PROC = f"results/processed/{args.run_id}"

os.makedirs(PLOTS, exist_ok=True)
os.makedirs(PROC, exist_ok=True)

# -------------------------------
# HELPERS
# -------------------------------
def load(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing file: {path}")
    with open(path) as f:
        return json.load(f)

def safe_float(x):
    try:
        return float(x)
    except:
        return None

def to_py(x):
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, (np.floating,)):
        return float(x)
    return x

# -------------------------------
# METRIC EXTRACTION
# -------------------------------
def extract(d, label="unknown"):
    try:
        hist = d.get("DurationHistogram", {})
        ps = hist.get("Percentiles", [])

        def gp(p):
            for x in ps:
                if x.get("Percentile") == p:
                    return x.get("Value")
            return None

        num = hist.get("Count") or d.get("NumRequests")
        if not num:
            raise ValueError(f"No request count in {label}")

        return {
            "avg": safe_float(hist.get("Avg")),
            "p50": gp(50),
            "p90": gp(90),
            "p99": gp(99),
            "p999": gp(99.9),
            "qps": safe_float(d.get("ActualQPS")),
            "target_qps": safe_float(d.get("RequestedQPS")),
            "count": int(num)
        }

    except Exception as e:
        print(f"[WARNING] Failed to parse {label}: {e}")
        return None

# -------------------------------
# METRICS
# -------------------------------
def queueing_delay(base, cur):
    return cur["avg"] - base["avg"]

def tail_ratio(m):
    return m["p99"] / m["p50"] if m["p50"] else None

def efficiency(m):
    if m["qps"] and m["target_qps"]:
        return m["qps"] / m["target_qps"]
    return None

def amplification(base, cur):
    return cur["p99"] / base["p99"]

# -------------------------------
# LOAD DATA
# -------------------------------
baseline = extract(load(f"{BASE}/baseline/baseline.json"), "baseline")

loads = [500, 1000, 2000, 4000]

svc_a = []
svc_b = []

for l in loads:
    svc_a.append(extract(load(f"{BASE}/load-ramp/svc-a_{l}.json"), f"a-{l}"))
    svc_b.append(extract(load(f"{BASE}/load-ramp/svc-b_{l}.json"), f"b-{l}"))

# -------------------------------
# COMPUTE METRICS
# -------------------------------
queue_a = [queueing_delay(baseline, m) for m in svc_a]
queue_b = [queueing_delay(baseline, m) for m in svc_b]

amp_a = [amplification(baseline, m) for m in svc_a]
amp_b = [amplification(baseline, m) for m in svc_b]

eff_a = [efficiency(m) for m in svc_a]
eff_b = [efficiency(m) for m in svc_b]

tail_a = [tail_ratio(m) for m in svc_a]
tail_b = [tail_ratio(m) for m in svc_b]

# -------------------------------
# PLOTS (ALL MULTI-CURVE)
# -------------------------------

# 1. Percentiles
plt.figure()
plt.plot(loads, [m["p99"] for m in svc_a], marker='o', label="svc-a P99")
plt.plot(loads, [m["p99"] for m in svc_b], marker='o', label="svc-b P99")
plt.plot(loads, [m["p90"] for m in svc_a], '--', label="svc-a P90")
plt.plot(loads, [m["p90"] for m in svc_b], '--', label="svc-b P90")
plt.legend()
plt.title("Latency Percentiles")
plt.savefig(f"{PLOTS}/percentiles_multi.png")
plt.close()

# 2. Efficiency
plt.figure()
plt.plot(loads, eff_a, marker='o', label="svc-a")
plt.plot(loads, eff_b, marker='o', label="svc-b")
plt.legend()
plt.title("Efficiency vs Load")
plt.savefig(f"{PLOTS}/efficiency_multi.png")
plt.close()

# 3. Amplification
plt.figure()
plt.plot(loads, amp_a, marker='o', label="svc-a")
plt.plot(loads, amp_b, marker='o', label="svc-b")
plt.legend()
plt.title("Tail Amplification")
plt.savefig(f"{PLOTS}/amplification_multi.png")
plt.close()

# 4. Queue delay
plt.figure()
plt.plot(loads, queue_a, marker='o', label="svc-a")
plt.plot(loads, queue_b, marker='o', label="svc-b")
plt.legend()
plt.title("Queueing Delay")
plt.savefig(f"{PLOTS}/queue_multi.png")
plt.close()

# 5. Tail ratio
plt.figure()
plt.plot(loads, tail_a, marker='o', label="svc-a")
plt.plot(loads, tail_b, marker='o', label="svc-b")
plt.legend()
plt.title("Tail Ratio")
plt.savefig(f"{PLOTS}/tail_ratio_multi.png")
plt.close()

# 6. Queue vs Amplification
plt.figure()
plt.plot(queue_a, amp_a, marker='o', label="svc-a")
plt.plot(queue_b, amp_b, marker='o', label="svc-b")
plt.legend()
plt.title("Queue vs Amplification")
plt.savefig(f"{PLOTS}/queue_vs_amp_multi.png")
plt.close()

# 7. Efficiency vs Amplification
plt.figure()
plt.plot(eff_a, amp_a, marker='o', label="svc-a")
plt.plot(eff_b, amp_b, marker='o', label="svc-b")
plt.legend()
plt.title("Efficiency vs Amplification")
plt.savefig(f"{PLOTS}/eff_vs_amp_multi.png")
plt.close()

print("\n✅ ALL MULTI-CURVE PLOTS GENERATED")
print("Saved →", PLOTS)