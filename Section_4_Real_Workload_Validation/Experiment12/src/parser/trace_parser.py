#!/usr/bin/env python3
"""
Jaeger trace parser for Experiment 12.
Parses Jaeger HTTP API JSON output and extracts per-hop span durations
for compose-post call chain analysis.

Usage:
  python3 trace_parser.py --input data/raw/run_001/jaeger-traces.json --output data/processed/csv/traces/
"""

import json
import csv
import argparse
import numpy as np
from pathlib import Path
from collections import defaultdict


def parse_traces(json_path: Path) -> dict[str, list[float]]:
    """Parse Jaeger traces JSON and return {service_name: [duration_ms, ...]}"""
    try:
        data = json.loads(json_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"[WARN] Cannot parse {json_path}: {e}")
        return {}

    traces = data.get("data", [])
    if not traces:
        print(f"[WARN] No traces found in {json_path}")
        return {}

    service_durations: dict[str, list[float]] = defaultdict(list)

    # Build process ID → service name map per trace
    for trace in traces:
        processes = trace.get("processes", {})
        pid_to_svc = {}
        for pid, proc in processes.items():
            pid_to_svc[pid] = proc.get("serviceName", "unknown")

        for span in trace.get("spans", []):
            process_id = span.get("processID", "")
            svc_name = pid_to_svc.get(process_id, "unknown")
            duration_us = span.get("duration", 0)
            duration_ms = duration_us / 1000.0
            operation = span.get("operationName", "unknown")

            service_durations[f"{svc_name}/{operation}"].append(duration_ms)

    return dict(service_durations)


def export_traces(json_path: Path, output_dir: Path):
    """Parse traces and export per-service statistics."""
    output_dir.mkdir(parents=True, exist_ok=True)

    service_durations = parse_traces(json_path)
    if not service_durations:
        return

    # Summary CSV: per-service mean/median/p99 span duration
    summary_file = output_dir / "trace-summary.csv"
    fieldnames = ["service_operation", "count", "mean_ms", "median_ms", "p95_ms", "p99_ms", "max_ms"]

    rows = []
    for svc_op, durations in sorted(service_durations.items()):
        arr = np.array(durations)
        rows.append({
            "service_operation": svc_op,
            "count": len(arr),
            "mean_ms": round(float(np.mean(arr)), 3),
            "median_ms": round(float(np.median(arr)), 3),
            "p95_ms": round(float(np.percentile(arr, 95)), 3),
            "p99_ms": round(float(np.percentile(arr, 99)), 3),
            "max_ms": round(float(np.max(arr)), 3),
        })
        print(f"  {svc_op:50s} count={len(arr):6d}  mean={np.mean(arr):.2f}ms  p99={np.percentile(arr, 99):.2f}ms")

    with open(summary_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n[OUTPUT] {summary_file} ({len(rows)} service/operations)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Jaeger traces JSON file")
    parser.add_argument("--output", required=True, help="Output directory for CSVs")
    args = parser.parse_args()

    export_traces(Path(args.input), Path(args.output))
    print("[DONE]")
