# Notebook: generate-paper-figures
#
# Master notebook: generates all paper figures for Experiment 12.
# Calls the src/plotting/ modules directly.
#
# Run in Jupyter:
#   jupyter notebook notebooks/generate-paper-figures.ipynb

import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path("../src/plotting").resolve()))
sys.path.insert(0, str(Path("../src/parser").resolve()))

from report_plots import generate_all_figures

DATA_DIR = Path("../data")
OUTPUT_DIR = Path("../results/figures")
RUN_ID = "run_001"  # Change to the run you want to plot

generate_all_figures(DATA_DIR, OUTPUT_DIR, RUN_ID)

print("\nAll paper figures generated.")
print(f"Output: {OUTPUT_DIR}")
