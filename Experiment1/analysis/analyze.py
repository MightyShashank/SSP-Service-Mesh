import os
import json
import numpy as np
import pandas as pd

RAW_DIR = "results/raw"
OUT_CSV = "results/processed/summary.csv"

throughputs = []
retransmissions = []
run_ids = []

# ---- Read all runs ----
for folder in sorted(os.listdir(RAW_DIR)):
    json_path = os.path.join(RAW_DIR, folder, "iperf.json")

    if not os.path.exists(json_path):
        continue

    try:
        with open(json_path) as f:
            data = json.load(f)

        summary = data["end"]["sum_sent"]

        # Convert to Gbps
        throughput_gbps = summary["bits_per_second"] / 1e9
        retrans = summary.get("retransmits", 0)

        throughputs.append(throughput_gbps)
        retransmissions.append(retrans)
        run_ids.append(folder)

    except Exception as e:
        print(f"Skipping {folder}: {e}")

# ---- Convert to numpy ----
t = np.array(throughputs)
r = np.array(retransmissions)

if len(t) == 0:
    print("No valid runs found.")
    exit(1)

# ---- Compute statistics ----
stats = {
    "mean_throughput": t.mean(),
    "std_throughput": t.std(),
    "var_throughput": t.var(),
    "min_throughput": t.min(),
    "max_throughput": t.max(),
    "mean_retrans": r.mean(),
    "std_retrans": r.std(),
}

# ---- Print summary ----
print("\n===== EXPERIMENT SUMMARY =====")

print("\n--- Throughput (Gbps) ---")
print(f"Runs: {len(t)}")
print(f"Mean: {stats['mean_throughput']:.3f}")
print(f"Std Dev: {stats['std_throughput']:.3f}")
print(f"Variance: {stats['var_throughput']:.5f}")
print(f"Min: {stats['min_throughput']:.3f}")
print(f"Max: {stats['max_throughput']:.3f}")

print("\n--- Retransmissions ---")
print(f"Mean: {stats['mean_retrans']:.0f}")
print(f"Std Dev: {stats['std_retrans']:.0f}")

# ---- Save per-run CSV ----
os.makedirs("results/processed", exist_ok=True)

df = pd.DataFrame({
    "run_id": run_ids,
    "throughput_gbps": t,
    "retransmissions": r
})

df.to_csv(OUT_CSV, index=False)

# ---- Save summary CSV ----
summary_df = pd.DataFrame([stats])
summary_df.to_csv("results/processed/summary_stats.csv", index=False)

print("\nSaved:")
print(f"- {OUT_CSV}")
print("- results/processed/summary_stats.csv")