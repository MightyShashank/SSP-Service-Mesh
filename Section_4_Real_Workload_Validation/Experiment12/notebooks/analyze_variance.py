# Notebook: analyze_variance
#
# Computes run-to-run variance, coefficient of variation, and
# bootstrap confidence intervals for Experiment 12.
#
# Contents:
#   1. Load per-run per-endpoint CSVs
#   2. Compute CV per metric
#   3. Bootstrap 95% CI (N=10,000)
#   4. Flag runs with CV > 5% on P50
#   5. Visualize run-to-run spread

import pandas as pd
import numpy as np
from pathlib import Path

CSV_DIR = Path("../data/processed/csv")
ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]
N_BOOTSTRAP = 10_000


def bootstrap_ci(data, n_boot=N_BOOTSTRAP, ci=95):
    boot_medians = [np.median(np.random.choice(data, len(data), replace=True))
                    for _ in range(n_boot)]
    return np.percentile(boot_medians, [(100-ci)/2, 100-(100-ci)/2])


np.random.seed(42)

for endpoint in ENDPOINTS:
    csv_file = CSV_DIR / f"{endpoint}.csv"
    if not csv_file.exists():
        print(f"{endpoint}: No data")
        continue

    df = pd.read_csv(csv_file)
    print(f"\n{'='*50}")
    print(f"  {endpoint} ({len(df)} runs)")
    print(f"{'='*50}")

    for col in ["p50", "p99", "p99_99"]:
        vals = df[col].dropna().values
        if len(vals) < 2:
            continue
        cv = 100 * np.std(vals, ddof=1) / np.mean(vals)
        ci_lo, ci_hi = bootstrap_ci(vals)
        flag = " ⚠ HIGH CV" if (col == "p50" and cv > 5) else ""
        print(f"  {col:8s}: median={np.median(vals):.3f}  "
              f"CI=[{ci_lo:.3f},{ci_hi:.3f}]  CV={cv:.1f}%{flag}")

print("\nNotebook placeholder — open in Jupyter for interactive analysis.")
