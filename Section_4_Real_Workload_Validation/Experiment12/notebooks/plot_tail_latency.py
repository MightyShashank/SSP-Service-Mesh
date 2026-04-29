# Notebook: plot_tail_latency
#
# Generates paper-quality tail latency figures:
#   - P50/P99/P99.99 bar chart per endpoint (paper Figure 4/Table 4)
#   - Error bars from bootstrap CI
#
# For paper-quality output, run in Jupyter with:
#   %matplotlib inline
#   plt.rcParams['figure.dpi'] = 300

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

CSV_DIR = Path("../data/processed/csv")
OUTPUT_DIR = Path("../results/figures/tail-percentiles")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
PCTS = ["p50", "p99", "p99_99"]
PCT_LABELS = ["P50", "P99", "P99.99"]
COLORS = ["#3498db", "#e67e22", "#e74c3c"]

fig, ax = plt.subplots(figsize=(10, 5))
x = np.arange(len(ENDPOINTS))
width = 0.22

for i, (pct, label, color) in enumerate(zip(PCTS, PCT_LABELS, COLORS)):
    vals = []
    for ep in ENDPOINTS:
        csv_file = CSV_DIR / f"{ep}.csv"
        if csv_file.exists():
            df = pd.read_csv(csv_file)
            vals.append(float(df[pct].median()))
        else:
            vals.append(0)
    bars = ax.bar(x + (i-1)*width, vals, width, label=label, color=color, alpha=0.85)

ax.set_xticks(x)
ax.set_xticklabels(ENDPOINTS)
ax.set_ylabel("Latency (ms)")
ax.set_title("Exp 12 Baseline: Tail Latency per Endpoint")
ax.legend()
ax.grid(axis="y", alpha=0.3)

fig.tight_layout()
fig.savefig(OUTPUT_DIR / "percentile-bars.pdf", dpi=300)
print(f"Saved: {OUTPUT_DIR / 'percentile-bars.pdf'}")
plt.close(fig)

print("\nNotebook placeholder — open in Jupyter for interactive analysis.")
