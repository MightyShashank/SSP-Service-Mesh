#!/usr/bin/env python3
"""
wrk2 output parser for Experiment 13.
Parses wrk2 --latency text output and extracts:
  - Latency percentiles: P50, P75, P90, P95, P99, P99.9, P99.99
  - Throughput (req/s)
  - Error count and error rate (%)
  - noisy_rps (from run-metadata.txt)

Usage:
  python3 wrk2_parser.py --runs-dir data/raw/case-A/sustained-ramp --output data/processed/csv/case-A/sustained-ramp/
"""

import os
import re
import csv
import argparse
from pathlib import Path


PERCENTILE_MAP = {
    "50.000%": "p50",
    "75.000%": "p75",
    "90.000%": "p90",
    "95.000%": "p95",
    "99.000%": "p99",
    "99.900%": "p99_9",
    "99.990%": "p99_99",
    "99.999%": "p99_999",
}

ENDPOINTS = ["compose-post", "home-timeline", "user-timeline"]


def parse_latency_line(line: str) -> tuple[str, float] | None:
    """Parse a wrk2 latency histogram line like '  50.000%   3.21ms'"""
    parts = line.strip().split()
    if len(parts) < 2:
        return None
    pct_str = parts[0]
    if pct_str not in PERCENTILE_MAP:
        return None
    val_str = parts[1]
    # Convert m/s/ms/us to ms
    if val_str.endswith("ms"):
        val_ms = float(val_str[:-2])
    elif val_str.endswith("us"):
        val_ms = float(val_str[:-2]) / 1000.0
    elif val_str.endswith("m"):
        val_ms = float(val_str[:-1]) * 60000.0
    elif val_str.endswith("s"):
        val_ms = float(val_str[:-1]) * 1000.0
    else:
        return None
    return PERCENTILE_MAP[pct_str], val_ms


def parse_wrk2_file(filepath: Path) -> dict:
    """Parse a single wrk2 output file and return a dict of metrics."""
    result = {k: None for k in PERCENTILE_MAP.values()}
    result["throughput_rps"] = None
    result["errors"] = 0
    result["error_rate_pct"] = None
    result["total_requests"] = None

    try:
        content = filepath.read_text()
    except FileNotFoundError:
        print(f"  [WARN] File not found: {filepath}")
        return result

    for line in content.splitlines():
        # Latency percentiles
        parsed = parse_latency_line(line)
        if parsed:
            key, val = parsed
            result[key] = val

        # Throughput: "Requests/sec:   198.34"
        m = re.search(r"Requests/sec:\s+([\d.]+)", line)
        if m:
            result["throughput_rps"] = float(m.group(1))

        # Total requests: "123456 requests in 180.00s"
        m = re.search(r"(\d+) requests in", line)
        if m:
            result["total_requests"] = int(m.group(1))

        # Errors: "Socket errors: connect 0, read 0, write 12, timeout 0"
        m = re.search(r"Non-2xx or 3xx responses:\s+(\d+)", line)
        if m:
            result["errors"] += int(m.group(1))

        m = re.search(r"Socket errors: connect (\d+), read (\d+), write (\d+), timeout (\d+)", line)
        if m:
            result["errors"] += sum(int(x) for x in m.groups())

    # Compute error rate
    if result["total_requests"] and result["total_requests"] > 0:
        result["error_rate_pct"] = 100.0 * result["errors"] / result["total_requests"]

    return result


def read_noisy_rps(trial_dir: Path) -> int | None:
    """Read noisy_rps from run-metadata.txt in the trial directory."""
    meta = trial_dir / "run-metadata.txt"
    if not meta.exists():
        return None
    for line in meta.read_text().splitlines():
        if line.startswith("Noisy RPS:"):
            try:
                return int(line.split(":", 1)[1].strip())
            except ValueError:
                return None
    return None


def parse_all_runs(runs_dir: Path, output_dir: Path):
    """Parse all trial_* directories and write per-endpoint CSVs."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Collect all rows: {endpoint: [row, ...]}
    all_rows = {ep: [] for ep in ENDPOINTS}

    run_dirs = sorted(runs_dir.glob("trial_*"))
    if not run_dirs:
        print(f"[ERROR] No trial_* directories found in {runs_dir}")
        return

    print(f"Found {len(run_dirs)} run(s): {[d.name for d in run_dirs]}")

    for run_dir in run_dirs:
        run_name = run_dir.name
        noisy_rps = read_noisy_rps(run_dir)
        for endpoint in ENDPOINTS:
            fname = run_dir / f"{endpoint}.txt"
            metrics = parse_wrk2_file(fname)
            row = {"run": run_name, "noisy_rps": noisy_rps, "endpoint": endpoint, **metrics}
            all_rows[endpoint].append(row)
            if metrics["p99"] is not None:
                print(f"  {run_name} (RPS={noisy_rps})/{endpoint}: P99={metrics['p99']:.2f}ms  "
                      f"P99.99={metrics.get('p99_99') or 'N/A'}ms  "
                      f"RPS={metrics['throughput_rps']}")
            else:
                print(f"  {run_name}/{endpoint}: [parse failed — check file]")

    # Write per-endpoint CSVs
    fieldnames = ["run", "noisy_rps", "endpoint", "p50", "p75", "p90", "p95", "p99",
                  "p99_9", "p99_99", "p99_999", "throughput_rps",
                  "total_requests", "errors", "error_rate_pct"]

    for endpoint in ENDPOINTS:
        out_file = output_dir / f"{endpoint}.csv"
        with open(out_file, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(all_rows[endpoint])
        print(f"\n[OUTPUT] {out_file}")

    # Write combined CSV
    combined_file = output_dir / "all-endpoints.csv"
    all_combined = [row for rows in all_rows.values() for row in rows]
    with open(combined_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_combined)
    print(f"[OUTPUT] {combined_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Parse wrk2 output files for Experiment 13")
    parser.add_argument("--runs-dir", required=True, help="Path to data/raw/ directory")
    parser.add_argument("--output", required=True, help="Output directory for CSVs")
    args = parser.parse_args()

    parse_all_runs(Path(args.runs_dir), Path(args.output))
    print("\n[DONE] Parsing complete")
