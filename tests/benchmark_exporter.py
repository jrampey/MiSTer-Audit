#!/usr/bin/env python3
"""Summarize exporter timing telemetry and enforce optional regression budgets.

Usage:
  python3 tests/benchmark_exporter.py REPORT_DIR [baseline.json]

The exporter already emits stage timing telemetry. This harness deliberately
benchmarks the real exporter output rather than inventing a second timing model.
"""
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
patterns = {
    "discovery_seconds": r"(?:DISCOVERY|Discovery)[^0-9]*([0-9]+(?:\.[0-9]+)?)",
    "save_index_seconds": r"(?:SAVE_INDEX|Save indexing)[^0-9]*([0-9]+(?:\.[0-9]+)?)",
    "database_seconds": r"(?:DATABASE|Database|DAT)[^0-9]*([0-9]+(?:\.[0-9]+)?)",
    "classification_seconds": r"(?:CLASSIFICATION|Classification)[^0-9]*([0-9]+(?:\.[0-9]+)?)",
    "report_seconds": r"(?:REPORT|Report)[^0-9]*([0-9]+(?:\.[0-9]+)?)",
    "full_verify_parallel_seconds": r"FULL_VERIFY_PARALLEL_SECONDS[^0-9]*([0-9]+(?:\.[0-9]+)?)",
}
text = "\n".join(p.read_text(errors="replace") for p in root.rglob("*") if p.is_file() and p.stat().st_size < 2_000_000)
metrics = {}
for key, pattern in patterns.items():
    m = re.search(pattern, text, re.I)
    if m:
        metrics[key] = float(m.group(1))
metrics["measured_stage_total_seconds"] = round(sum(v for k,v in metrics.items() if k.endswith("_seconds") and k != "full_verify_parallel_seconds"), 3)
print(json.dumps(metrics, indent=2, sort_keys=True))
Path("benchmark-results.json").write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n")

if len(sys.argv) > 2 and Path(sys.argv[2]).exists():
    baseline = json.loads(Path(sys.argv[2]).read_text())
    regressions=[]
    for key, old in baseline.items():
        new=metrics.get(key)
        if isinstance(old,(int,float)) and new is not None and old > 0 and new > old * 1.25:
            regressions.append(f"{key}: {old} -> {new} (>25% slower)")
    if regressions:
        print("Performance regression detected:", *regressions, sep="\n- ", file=sys.stderr)
        raise SystemExit(1)
