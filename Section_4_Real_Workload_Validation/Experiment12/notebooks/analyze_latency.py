# Notebook: analyze_latency
#
# This notebook performs latency percentile analysis and CDF plotting
# for Experiment 12 baseline data.
#
# Contents:
#   1. Load wrk2 parsed CSVs from data/processed/csv/
#   2. Compute P50/P99/P99.9/P99.99 per endpoint
#   3. Plot latency CDF (log-x) for compose-post
#   4. Compare across repetitions
#
# To run:
#   jupyter notebook notebooks/analyze_latency.ipynb
#
# Or convert to script:
#   jupyter nbconvert --to script analyze_latency.ipynb

# Placeholder — create the actual .ipynb via Jupyter or VS Code.
# This file exists to document the intended notebook content.

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# Configuration
CSV_DIR = Path("../data/processed/csv")
ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]

# Load data
for endpoint in ENDPOINTS:
    csv_file = CSV_DIR / f"{endpoint}.csv"
    if csv_file.exists():
        df = pd.read_csv(csv_file)
        print(f"\n{endpoint}:")
        print(df[["run", "p50", "p99", "p99_99"]].to_string(index=False))
    else:
        print(f"\n{endpoint}: No data found at {csv_file}")

print("\nNotebook placeholder — open in Jupyter for interactive analysis.")
