#!/usr/bin/env python3
"""
Prometheus metrics parser for Experiment 12.
Parses Prometheus API JSON snapshots from capture-prometheus-snapshot.sh.

Usage:
  python3 prom_parser.py --input data/raw/run_001/prom-snapshot/ --output data/processed/csv/prom/
"""

import json
import csv
import argparse
from pathlib import Path


def parse_instant_query(json_path: Path) -> list[dict]:
    """Parse a Prometheus instant query JSON response into rows."""
    try:
        data = json.loads(json_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"[WARN] Cannot parse {json_path}: {e}")
        return []

    if data.get("status") != "success":
        print(f"[WARN] Query failed in {json_path}")
        return []

    rows = []
    for result in data.get("data", {}).get("result", []):
        metric = result.get("metric", {})
        timestamp, value = result.get("value", [0, "0"])
        rows.append({
            "metric_name": metric.get("__name__", "unknown"),
            "pod": metric.get("pod", ""),
            "container": metric.get("container", ""),
            "namespace": metric.get("namespace", ""),
            "timestamp": timestamp,
            "value": float(value),
        })
    return rows


def parse_all(input_dir: Path, output_dir: Path):
    """Parse all Prometheus JSON snapshots in input_dir."""
    output_dir.mkdir(parents=True, exist_ok=True)

    json_files = list(input_dir.glob("*.json"))
    if not json_files:
        print(f"[WARN] No JSON files found in {input_dir}")
        return

    fieldnames = ["metric_name", "pod", "container", "namespace", "timestamp", "value"]

    for json_file in json_files:
        rows = parse_instant_query(json_file)
        if not rows:
            continue
        out_file = output_dir / f"{json_file.stem}.csv"
        with open(out_file, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
        print(f"[OUTPUT] {out_file} ({len(rows)} rows)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Directory with Prometheus JSON snapshots")
    parser.add_argument("--output", required=True, help="Output directory for CSVs")
    args = parser.parse_args()

    parse_all(Path(args.input), Path(args.output))
    print("[DONE]")
