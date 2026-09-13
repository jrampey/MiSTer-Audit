#!/usr/bin/env python3
"""Validate the MiSTer-aware hash database before it is released."""

import argparse
import collections
import csv
import re
import sys
from pathlib import Path

EXPECTED_HEADER = [
    "sha1", "canonical_title", "canonical_rom_name", "dat_source", "size",
    "crc32", "md5", "mister_system", "mister_core", "expected_folder",
    "region", "release_type", "license_status",
]
SHA1_RE = re.compile(r"^[0-9a-fA-F]{40}$")
CRC32_RE = re.compile(r"^[0-9a-fA-F]{8}$")
MD5_RE = re.compile(r"^[0-9a-fA-F]{32}$")


def fail(errors, message, limit=100):
    if len(errors) < limit:
        errors.append(message)


def validate(path: Path, min_records: int) -> int:
    errors = []
    warnings = []
    sha1_seen = {}
    system_counts = collections.Counter()
    source_counts = collections.Counter()
    row_count = 0

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        try:
            header = next(reader)
        except StopIteration:
            print("ERROR: database is empty", file=sys.stderr)
            return 1
        if header != EXPECTED_HEADER:
            fail(errors, f"header mismatch: expected {EXPECTED_HEADER!r}, got {header!r}")

        for line_no, row in enumerate(reader, 2):
            if not row or all(not value.strip() for value in row):
                continue
            row_count += 1
            if len(row) != len(EXPECTED_HEADER):
                fail(errors, f"line {line_no}: expected {len(EXPECTED_HEADER)} columns, got {len(row)}")
                continue
            record = dict(zip(EXPECTED_HEADER, row))
            sha1 = record["sha1"].strip().lower()
            if not SHA1_RE.fullmatch(sha1):
                fail(errors, f"line {line_no}: invalid SHA-1 {record['sha1']!r}")
            elif sha1 in sha1_seen:
                fail(errors, f"line {line_no}: duplicate SHA-1 {sha1} (first seen line {sha1_seen[sha1]})")
            else:
                sha1_seen[sha1] = line_no

            for field in ("canonical_title", "canonical_rom_name", "dat_source", "mister_system", "expected_folder"):
                if not record[field].strip():
                    fail(errors, f"line {line_no}: required field {field} is blank")

            size = record["size"].strip()
            if size:
                try:
                    if int(size) < 0:
                        raise ValueError
                except ValueError:
                    fail(errors, f"line {line_no}: invalid size {size!r}")
            crc32 = record["crc32"].strip()
            md5 = record["md5"].strip()
            if crc32 and not CRC32_RE.fullmatch(crc32):
                fail(errors, f"line {line_no}: invalid CRC32 {crc32!r}")
            if md5 and not MD5_RE.fullmatch(md5):
                fail(errors, f"line {line_no}: invalid MD5 {md5!r}")

            system = record["mister_system"].strip()
            source = record["dat_source"].strip()
            system_counts[system] += 1
            source_counts[source] += 1

            folder = record["expected_folder"].strip()
            if folder.startswith("/") or ".." in Path(folder).parts:
                fail(errors, f"line {line_no}: unsafe expected_folder {folder!r}")

    if row_count < min_records:
        fail(errors, f"record count {row_count:,} is below safety floor {min_records:,}")
    if len(sha1_seen) != row_count:
        fail(errors, f"unique SHA-1 count {len(sha1_seen):,} does not equal record count {row_count:,}")
    if not system_counts:
        fail(errors, "no MiSTer systems found")

    print(f"records={row_count:,}")
    print(f"unique_sha1={len(sha1_seen):,}")
    print(f"systems={len(system_counts)}")
    print("per_system=" + ", ".join(f"{k}:{v}" for k, v in sorted(system_counts.items())))
    print(f"dat_sources={len(source_counts)}")

    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        if len(errors) >= 100:
            print("ERROR: validation stopped reporting after 100 errors", file=sys.stderr)
        return 1
    print("Hash database validation passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", default="mister_hash_database.tsv")
    parser.add_argument("--min-records", type=int, default=40000)
    args = parser.parse_args()
    return validate(Path(args.path), args.min_records)


if __name__ == "__main__":
    raise SystemExit(main())
