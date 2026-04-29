#!/usr/bin/env python3
"""
Experiment 13 — Jaeger trace parser with noisy-neighbor context.

Parses Jaeger HTTP API JSON and extracts per-service span latencies
for the compose-post call chain. Supports labeling traces as
'baseline' (no noisy load) or 'noisy' (with svc-noisy running).

Key services in the compose-post call chain:
  nginx-thrift → compose-post-service → social-graph-service
                                       → user-service
                                       → media-service
                                       → text-service
                                       → url-shorten-service
                                       → unique-id-service
                                       → post-storage-service

Usage:
  python3 trace_parser.py \
    --input  data/raw/case-A/sustained-ramp/trial_001/jaeger-traces.json \
    --output data/processed/csv/case-A/sustained-ramp/trial_001/traces/ \
    --label  noisy \
    --noisy-rps 300
"""

import json
import csv
import argparse
import numpy as np
from pathlib import Path
from collections import defaultdict


# Services that appear on the critical path of /compose-post
# Map from Jaeger serviceName → short label for plots
SERVICE_LABELS = {
    "nginx-thrift":           "nginx-thrift",
    "compose-post-service":   "compose-post",
    "social-graph-service":   "social-graph",
    "user-service":           "user-service",
    "media-service":          "media-service",
    "text-service":           "text-service",
    "url-shorten-service":    "url-shorten",
    "unique-id-service":      "unique-id",
    "post-storage-service":   "post-storage",
    "user-mention-service":   "user-mention",
}


def parse_traces(json_path: Path) -> dict[str, list[float]]:
    """
    Parse Jaeger traces JSON.
    Returns {service_name: [span_duration_ms, ...]}
    Only spans from the compose-post call chain are included.
    """
    try:
        data = json.loads(json_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"[WARN] Cannot parse {json_path}: {e}")
        return {}

    traces = data.get("data", [])
    if not traces:
        print(f"[WARN] No traces in {json_path}")
        return {}

    service_durations: dict[str, list[float]] = defaultdict(list)

    for trace in traces:
        processes = trace.get("processes", {})
        pid_to_svc = {pid: proc.get("serviceName", "unknown")
                      for pid, proc in processes.items()}

        for span in trace.get("spans", []):
            pid      = span.get("processID", "")
            svc_raw  = pid_to_svc.get(pid, "unknown")
            svc      = SERVICE_LABELS.get(svc_raw, svc_raw)
            dur_ms   = span.get("duration", 0) / 1000.0
            op       = span.get("operationName", "unknown")
            service_durations[svc].append(dur_ms)

    return dict(service_durations)


def summarise(durations: list[float]) -> dict:
    arr = np.array(durations)
    return {
        "count":     len(arr),
        "mean_ms":   round(float(np.mean(arr)),               3),
        "median_ms": round(float(np.median(arr)),             3),
        "p95_ms":    round(float(np.percentile(arr, 95)),     3),
        "p99_ms":    round(float(np.percentile(arr, 99)),     3),
        "p99_9_ms":  round(float(np.percentile(arr, 99.9)),   3),
        "max_ms":    round(float(np.max(arr)),                3),
    }


def export_traces(json_path: Path, output_dir: Path, label: str = "unknown", noisy_rps: int = 0):
    output_dir.mkdir(parents=True, exist_ok=True)

    service_durations = parse_traces(json_path)
    if not service_durations:
        print(f"[SKIP] No data in {json_path}")
        return

    rows = []
    for svc, durs in sorted(service_durations.items()):
        stats = summarise(durs)
        rows.append({
            "label":     label,
            "noisy_rps": noisy_rps,
            "service":   svc,
            **stats,
        })
        print(f"  {svc:25s} n={stats['count']:6d}  "
              f"median={stats['median_ms']:.2f}ms  p99={stats['p99_ms']:.2f}ms")

    # Per-span raw CSV (for detailed analysis)
    raw_file = output_dir / "spans-raw.csv"
    with open(raw_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["label", "noisy_rps", "service", "duration_ms"])
        for svc, durs in service_durations.items():
            for d in durs:
                writer.writerow([label, noisy_rps, svc, round(d, 3)])

    # Summary CSV
    summary_file = output_dir / "trace-summary.csv"
    fieldnames = ["label", "noisy_rps", "service",
                  "count", "mean_ms", "median_ms", "p95_ms", "p99_ms", "p99_9_ms", "max_ms"]
    with open(summary_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n[OUTPUT] {summary_file} ({len(rows)} services)")
    print(f"[OUTPUT] {raw_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",     required=True, help="Jaeger traces JSON file")
    parser.add_argument("--output",    required=True, help="Output CSV directory")
    parser.add_argument("--label",     default="unknown",
                        help="'baseline' or 'noisy' — tags the condition in output CSV")
    parser.add_argument("--noisy-rps", type=int, default=0,
                        help="Noisy-neighbor RPS during this trial (0 = no noise)")
    args = parser.parse_args()

    export_traces(Path(args.input), Path(args.output), args.label, args.noisy_rps)
    print("[DONE]")
