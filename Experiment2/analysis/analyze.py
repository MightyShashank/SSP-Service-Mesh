import os
import json
import numpy as np
import pandas as pd
import re

RAW_DIR = "results/raw"
OUT_CSV = "results/processed/summary.csv"

runs = []

def parse_latency(value):
    if "ms" in value:
        return float(value.replace("ms", ""))
    if "us" in value:
        return float(value.replace("us", "")) / 1000
    if "s" in value:
        return float(value.replace("s", "")) * 1000
    return None

def parse_prometheus(file_path):
    try:
        with open(file_path) as f:
            data = json.load(f)

        values = []
        for result in data["data"]["result"]:
            for point in result["values"]:
                values.append(float(point[1]))

        if len(values) == 0:
            return None, None

        return np.mean(values), np.std(values)

    except:
        return None, None

for folder in sorted(os.listdir(RAW_DIR)):
    folder_path = os.path.join(RAW_DIR, folder)
    wrk_path = os.path.join(folder_path, "wrk.txt")

    if not os.path.exists(wrk_path):
        continue

    with open(wrk_path) as f:
        text = f.read()

    try:
        lat_line = re.search(r"Latency\s+([\d\.]+\w+)\s+([\d\.]+\w+)\s+([\d\.]+\w+)", text)
        lat_avg = parse_latency(lat_line.group(1))
        lat_std = parse_latency(lat_line.group(2))
        lat_max = parse_latency(lat_line.group(3))

        p50 = parse_latency(re.search(r"50%\s+([\d\.]+\w+)", text).group(1))
        p75 = parse_latency(re.search(r"75%\s+([\d\.]+\w+)", text).group(1))
        p90 = parse_latency(re.search(r"90%\s+([\d\.]+\w+)", text).group(1))
        p99 = parse_latency(re.search(r"99%\s+([\d\.]+\w+)", text).group(1))

        rps = float(re.search(r"Requests/sec:\s+([\d\.]+)", text).group(1))

        cpu_mean, cpu_std = parse_prometheus(os.path.join(folder_path, "cpu.json"))
        tx_mean, _ = parse_prometheus(os.path.join(folder_path, "tx.json"))
        rx_mean, _ = parse_prometheus(os.path.join(folder_path, "rx.json"))

        runs.append({
            "run_id": folder,
            "rps": rps,
            "lat_avg": lat_avg,
            "lat_std": lat_std,
            "lat_max": lat_max,
            "p50": p50,
            "p75": p75,
            "p90": p90,
            "p99": p99,
            "cpu_mean": cpu_mean,
            "cpu_std": cpu_std,
            "tx_mean": tx_mean,
            "rx_mean": rx_mean
        })

    except Exception as e:
        print(f"Skipping {folder}: {e}")

df = pd.DataFrame(runs)

if df.empty:
    print("No valid runs found.")
    exit(1)

os.makedirs("results/processed", exist_ok=True)
df.to_csv(OUT_CSV, index=False)

summary = df.describe()
summary.to_csv("results/processed/summary_stats.csv")

print("\nSaved:")
print(f"- {OUT_CSV}")
print("- results/processed/summary_stats.csv")