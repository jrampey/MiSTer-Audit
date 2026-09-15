#!/usr/bin/env python3
"""Build/update mister_hash_database.tsv from No-Intro DAT/XML sources.

Only systems represented by recognized DATs in Sources/No-Intro are replaced.
Existing records for all other systems are preserved. Output is deterministic.
"""

from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HEADER = [
    "sha1", "canonical_title", "canonical_rom_name", "dat_source", "size",
    "crc32", "md5", "mister_system", "mister_core", "expected_folder",
    "region", "release_type", "license_status",
]

# Ordered: more-specific names must precede broader names.
SYSTEM_RULES = [
    ("Nintendo - Nintendo Entertainment System", "NES", "NES", "NES"),
    ("Nintendo - Family Computer Disk System", "NES", "NES", "NES"),
    ("Nintendo - Super Nintendo Entertainment System", "SNES", "SNES", "SNES"),
    ("Nintendo - Nintendo 64", "N64", "N64", "N64"),
    ("Nintendo - Game Boy Color", "GBC", "Gameboy2P", "Gameboy"),
    ("Nintendo - Game Boy Advance", "GBA", "GBA", "GBA"),
    ("Nintendo - Game Boy", "GAMEBOY", "Gameboy2P", "Gameboy"),
    ("Sega - Mega Drive - Genesis", "MegaDrive", "Genesis", "MegaDrive"),
    ("Sega - 32X", "S32X", "S32X", "S32X"),
    ("Sega - Master System - Mark III", "SMS", "SMS", "SMS"),
    ("Atari - Atari 2600", "Atari2600", "Atari2600", "Atari2600"),
    ("Mattel - Intellivision", "Intellivision", "Intellivision", "Intellivision"),
    ("NEC - PC Engine - TurboGrafx-16", "TGFX16", "TurboGrafx16", "TGFX16"),
    ("NEC - PC Engine SuperGrafx", "TGFX16", "TurboGrafx16", "TGFX16"),
    ("Commodore - Amiga", "Amiga", "Minimig", "Amiga"),
    ("Commodore - Commodore 64", "C64", "C64", "C64"),
    ("Acorn - Archimedes", "ARCHIE", "Archie", "Archie"),
]

REGIONS = ["USA", "Europe", "Japan", "Canada", "Australia", "Korea", "Brazil", "World"]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def map_system(dat_name: str):
    low = dat_name.lower()
    for needle, system, core, folder in SYSTEM_RULES:
        if needle.lower() in low:
            return system, core, folder
    return None


def region_from_name(name: str) -> str:
    found = []
    for group in re.findall(r"\(([^)]*)\)", name):
        for region in REGIONS:
            if re.search(rf"(?:^|,\s*){re.escape(region)}(?:$|,)", group, re.I):
                found.append(region)
    if "World" in found:
        return "World"
    return found[0] if found else "Unknown"


def release_type(name: str) -> str:
    low = name.lower()
    if any(x in low for x in ("(proto", "(beta", "(demo", "(sample")):
        return "Prototype/Demo"
    if any(x in low for x in ("(unl", "homebrew", "aftermarket")):
        return "Homebrew/Unlicensed"
    return "Retail/Standard"


def license_status(name: str) -> str:
    low = name.lower()
    if any(x in low for x in ("(unl", "homebrew", "aftermarket")):
        return "Unlicensed"
    return "Licensed"


def read_existing(path: Path):
    records = []
    if not path.exists():
        return records
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if reader.fieldnames != HEADER:
            raise SystemExit(f"Existing database header does not match schema: {reader.fieldnames!r}")
        records.extend(reader)
    return records


def parse_dat(path: Path):
    tree = ET.parse(path)
    root = tree.getroot()
    header = root.find("header")
    dat_name = (header.findtext("name") if header is not None else None) or path.stem
    dat_version = (header.findtext("version") if header is not None else None) or ""
    mapped = map_system(dat_name)
    if not mapped:
        return None
    system, core, folder = mapped
    records = []
    for game in root.findall("game"):
        title = game.get("name") or game.findtext("description") or ""
        for rom in game.findall("rom"):
            sha1 = (rom.get("sha1") or "").lower().strip()
            if not re.fullmatch(r"[0-9a-f]{40}", sha1):
                continue
            rom_name = rom.get("name") or title
            records.append({
                "sha1": sha1,
                "canonical_title": title,
                "canonical_rom_name": rom_name,
                "dat_source": f"No-Intro: {dat_name} ({dat_version})" if dat_version else f"No-Intro: {dat_name}",
                "size": rom.get("size") or "",
                "crc32": (rom.get("crc") or "").lower(),
                "md5": (rom.get("md5") or "").lower(),
                "mister_system": system,
                "mister_core": core,
                "expected_folder": folder,
                "region": region_from_name(title),
                "release_type": release_type(title),
                "license_status": license_status(title),
            })
    return {"name": dat_name, "version": dat_version, "system": system, "records": records}


def record_key(r):
    return tuple(r.get(k, "") for k in HEADER)


def load_manifest(path: Path):
    if not path.exists():
        return {"schema": 1, "sources": {}}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return {"schema": 1, "sources": {}}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", default="Sources/No-Intro")
    ap.add_argument("--database", default="mister_hash_database.tsv")
    ap.add_argument("--manifest", default="Sources/no_intro_manifest.json")
    ap.add_argument("--delta", default="build/hash_database_delta.md")
    ap.add_argument("--max-system-drop", type=float, default=0.10,
                    help="Fail if an updated system loses more than this fraction of records")
    ap.add_argument("--allow-large-drop", action="store_true")
    args = ap.parse_args()

    source_root = Path(args.sources)
    db_path = Path(args.database)
    manifest_path = Path(args.manifest)
    delta_path = Path(args.delta)
    dats = sorted([*source_root.rglob("*.dat"), *source_root.rglob("*.xml")]) if source_root.exists() else []
    if not dats:
        print(f"No DAT/XML files found under {source_root}", file=sys.stderr)
        return 2

    old_manifest = load_manifest(manifest_path)
    existing = read_existing(db_path)
    old_by_system = collections.Counter(r["mister_system"] for r in existing)
    old_by_sha = {r["sha1"].lower(): r for r in existing}

    parsed = []
    new_manifest_sources = {}
    changed_sources = []
    ignored_sources = []
    for path in dats:
        rel = path.as_posix()
        digest = sha256_file(path)
        result = parse_dat(path)
        if result is None:
            ignored_sources.append(rel)
            continue
        parsed.append(result)
        previous = old_manifest.get("sources", {}).get(rel, {})
        if previous.get("sha256") != digest:
            changed_sources.append(rel)
        new_manifest_sources[rel] = {
            "sha256": digest,
            "dat_name": result["name"],
            "dat_version": result["version"],
            "mister_system": result["system"],
            "parsed_records": len(result["records"]),
        }

    touched_systems = {p["system"] for p in parsed}
    generated = [r for p in parsed for r in p["records"]]
    preserved = [r for r in existing if r["mister_system"] not in touched_systems]

    combined = generated + preserved
    combined.sort(key=lambda r: (r["sha1"].lower(), r["mister_system"], r["canonical_rom_name"], r["dat_source"]))
    deduped = {}
    duplicate_conflicts = 0
    for r in combined:
        sha = r["sha1"].lower()
        if sha in deduped:
            if record_key(deduped[sha]) != record_key(r):
                duplicate_conflicts += 1
            continue
        deduped[sha] = r
    final_records = list(deduped.values())
    final_records.sort(key=lambda r: (r["mister_system"].lower(), r["canonical_rom_name"].lower(), r["sha1"]))

    new_by_system = collections.Counter(r["mister_system"] for r in final_records)
    regressions = []
    for system in sorted(touched_systems):
        old = old_by_system.get(system, 0)
        new = new_by_system.get(system, 0)
        if old and new < old * (1.0 - args.max_system_drop):
            regressions.append((system, old, new))

    new_by_sha = {r["sha1"].lower(): r for r in final_records}
    added = sorted(set(new_by_sha) - set(old_by_sha))
    removed = sorted(set(old_by_sha) - set(new_by_sha))
    changed = sorted(sha for sha in set(old_by_sha) & set(new_by_sha)
                     if record_key(old_by_sha[sha]) != record_key(new_by_sha[sha]))

    delta_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Hash Database Delta", "",
        f"- Previous records: **{len(existing):,}**",
        f"- New records: **{len(final_records):,}**",
        f"- Added SHA-1 records: **{len(added):,}**",
        f"- Removed SHA-1 records: **{len(removed):,}**",
        f"- Metadata-changed records: **{len(changed):,}**",
        f"- Duplicate SHA-1 conflicts resolved deterministically: **{duplicate_conflicts:,}**",
        f"- Recognized source DATs: **{len(parsed)}**",
        f"- Changed/new source DATs: **{len(changed_sources)}**", "",
        "## Per-system counts", "",
        "| System | Previous | New | Delta |", "|---|---:|---:|---:|",
    ]
    for system in sorted(set(old_by_system) | set(new_by_system)):
        old, new = old_by_system.get(system, 0), new_by_system.get(system, 0)
        lines.append(f"| {system} | {old:,} | {new:,} | {new-old:+,} |")
    lines += ["", "## Changed/new sources", ""]
    lines += [f"- `{p}`" for p in changed_sources] or ["- None"]
    if ignored_sources:
        lines += ["", "## Ignored/unmapped sources", ""] + [f"- `{p}`" for p in ignored_sources]
    if regressions:
        lines += ["", "## BLOCKING per-system regressions", ""]
        for system, old, new in regressions:
            lines.append(f"- {system}: {old:,} -> {new:,}")
    delta_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    if regressions and not args.allow_large_drop:
        print(delta_path.read_text(encoding="utf-8"))
        print("ERROR: per-system coverage regression exceeded threshold; database was not replaced.", file=sys.stderr)
        return 1

    db_path.parent.mkdir(parents=True, exist_ok=True)
    with db_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=HEADER, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(final_records)

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": 1,
        "builder": "tools/build_hash_database.py",
        "sources": dict(sorted(new_manifest_sources.items())),
        "database_records": len(final_records),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"Recognized DATs: {len(parsed)}")
    print(f"Touched systems: {', '.join(sorted(touched_systems))}")
    print(f"Changed/new DATs: {len(changed_sources)}")
    print(f"Records: {len(existing):,} -> {len(final_records):,}")
    print(f"Added={len(added):,} Removed={len(removed):,} MetadataChanged={len(changed):,}")
    print(f"Delta report: {delta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
