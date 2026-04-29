#!/usr/bin/env python3
"""
Percentile extraction helpers for Experiment 12.
Utility functions for P50/P99/P99.9/P99.99 computation from raw data.
"""

import numpy as np
from typing import Optional


STANDARD_PERCENTILES = [50, 75, 90, 95, 99, 99.9, 99.99]
PERCENTILE_LABELS = {
    50: "p50", 75: "p75", 90: "p90", 95: "p95",
    99: "p99", 99.9: "p99_9", 99.99: "p99_99",
}


def compute_percentiles(data: list[float], percentiles: Optional[list[float]] = None) -> dict[str, float]:
    """Compute named percentiles from a list of values."""
    if percentiles is None:
        percentiles = STANDARD_PERCENTILES

    arr = np.array([x for x in data if x is not None and not np.isnan(x)])
    if len(arr) == 0:
        return {PERCENTILE_LABELS.get(p, f"p{p}"): float("nan") for p in percentiles}

    result = {}
    for p in percentiles:
        label = PERCENTILE_LABELS.get(p, f"p{p}")
        result[label] = float(np.percentile(arr, p))
    return result


def median_across_runs(runs_data: list[dict[str, float]], metric: str) -> float:
    """Compute median of a metric across multiple runs."""
    values = [r[metric] for r in runs_data if metric in r and r[metric] is not None]
    if not values:
        return float("nan")
    return float(np.median(values))


def format_percentile_table(data: dict[str, float]) -> str:
    """Format percentile values into a readable table string."""
    lines = []
    for label in sorted(data.keys()):
        lines.append(f"  {label:10s}: {data[label]:.3f} ms")
    return "\n".join(lines)
