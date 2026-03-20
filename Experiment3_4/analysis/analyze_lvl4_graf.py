import argparse
import json
import os

import matplotlib.pyplot as plt

plt.style.use("seaborn-v0_8-darkgrid")

parser = argparse.ArgumentParser()
parser.add_argument("--run_id", required=True)
args = parser.parse_args()

BASE = f"results/raw/{args.run_id}"
PLOTS = f"results/plots_lvl4/{args.run_id}"
os.makedirs(PLOTS, exist_ok=True)

# -------------------------------
# HELPERS
# -------------------------------
def load(p):
    with open(p) as f:
        return json.load(f)

def sf(x):
    try:
        return float(x)
    except:
        return None

def extract(d):
    h = d["DurationHistogram"]

    def gp(p):
        for x in h["Percentiles"]:
            if x["Percentile"] == p:
                return x["Value"]

    return {
        "avg": sf(h["Avg"]),
        "p50": gp(50),
        "p90": gp(90),
        "p99": gp(99),
        "qps": sf(d["ActualQPS"]),
        "target": sf(d["RequestedQPS"])
    }

def eff(m):
    return m["qps"] / m["target"] if m["qps"] and m["target"] else None

def amp(base, cur):
    return cur["p99"] / base["p99"]

def qdelay(base, cur):
    return cur["avg"] - base["avg"]

# -------------------------------
# LOAD DATA
# -------------------------------
baseline = extract(load(f"{BASE}/baseline/baseline.json"))

loads = [500, 1000, 2000, 4000]

data = []

for l in loads:
    m = extract(load(f"{BASE}/load-ramp/svc-a_{l}.json"))
    data.append({
        "load": l,
        "q": qdelay(baseline, m),
        "e": eff(m),
        "a": amp(baseline, m),
        "p99": m["p99"]
    })

# -------------------------------
# SORT BY LOAD (important)
# -------------------------------
data = sorted(data, key=lambda x: x["load"])

# -------------------------------
# 1. Queue → Amplification (MULTI-CURVE = LOAD SEGMENTS)
# -------------------------------
plt.figure()

for i in range(len(data) - 1):
    x = [data[i]["q"], data[i+1]["q"]]
    y = [data[i]["a"], data[i+1]["a"]]

    plt.plot(x, y, marker='o', label=f"{data[i]['load']}→{data[i+1]['load']}")

plt.xlabel("Queueing Delay")
plt.ylabel("Amplification")
plt.title("Queue → Amplification (Load Segments)")
plt.legend()
plt.savefig(f"{PLOTS}/queue_amp_segments.png")
plt.close()

# -------------------------------
# 2. Efficiency → Amplification
# -------------------------------
plt.figure()

for i in range(len(data) - 1):
    x = [data[i]["e"], data[i+1]["e"]]
    y = [data[i]["a"], data[i+1]["a"]]

    plt.plot(x, y, marker='o', label=f"{data[i]['load']}→{data[i+1]['load']}")

plt.xlabel("Efficiency")
plt.ylabel("Amplification")
plt.title("Efficiency → Amplification (Phases)")
plt.legend()
plt.savefig(f"{PLOTS}/eff_amp_segments.png")
plt.close()

# -------------------------------
# 3. Queue → Efficiency
# -------------------------------
plt.figure()

for i in range(len(data) - 1):
    x = [data[i]["q"], data[i+1]["q"]]
    y = [data[i]["e"], data[i+1]["e"]]

    plt.plot(x, y, marker='o', label=f"{data[i]['load']}→{data[i+1]['load']}")

plt.xlabel("Queueing Delay")
plt.ylabel("Efficiency")
plt.title("Queue → Efficiency Collapse")
plt.legend()
plt.savefig(f"{PLOTS}/queue_eff_segments.png")
plt.close()

# -------------------------------
# 4. Queue → P99
# -------------------------------
plt.figure()

for i in range(len(data) - 1):
    x = [data[i]["q"], data[i+1]["q"]]
    y = [data[i]["p99"], data[i+1]["p99"]]

    plt.plot(x, y, marker='o', label=f"{data[i]['load']}→{data[i+1]['load']}")

plt.xlabel("Queueing Delay")
plt.ylabel("P99 Latency")
plt.title("Queue → Latency Explosion (Segments)")
plt.legend()
plt.savefig(f"{PLOTS}/queue_p99_segments.png")
plt.close()

print("\n✅ TRUE MULTI-CURVE CORRELATION PLOTS GENERATED")