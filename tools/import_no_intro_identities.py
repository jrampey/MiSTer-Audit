#!/usr/bin/env python3
"""Offline No-Intro DAT -> optional MiSTer game identity alias table.

This imports *identity*, never original-U.S.-retail eligibility or release dates.
Use a trusted DAT archive and review ambiguous identities before publishing.
"""
import argparse
import csv
import hashlib
import io
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# Prefer one ROM-byte-order DAT per console to avoid conflicting root ids.
DAT_SYSTEMS = {
    "Nintendo - Nintendo 64 (BigEndian)": "N64",
    "Nintendo - Nintendo Entertainment System (Headerless)": "NES",
    "Nintendo - Super Nintendo Entertainment System": "SNES",
    "Nintendo - Game Boy": "GAMEBOY",
    "Nintendo - Game Boy Color": "GBC",
    "Nintendo - Game Boy Advance": "GBA",
    "Nintendo - Virtual Boy": "VirtualBoy",
    "Nintendo - Family Computer Disk System (FDS)": "NES",
    "Sega - Mega Drive - Genesis": "MegaDrive",
    "Sega - Master System - Mark III": "SMS",
    "Atari - Atari 2600": "Atari2600",
}


def normalize_title(title: str) -> str:
    title = title.strip()
    while True:
        next_title = re.sub(r"\s+\([^()]*\)$", "", title)
        if next_title == title:
            break
        title = next_title
    return re.sub(r"\s+", " ", title).lower()


def match_system(dat_filename: str) -> str | None:
    base = Path(dat_filename).name
    for prefix, system in DAT_SYSTEMS.items():
        if base.startswith(prefix + " ("):
            suffix = base[len(prefix) + 2:]
            if re.fullmatch(r"\d{8}-\d{6}\)\.dat", suffix):
                return system
    return None


def extract(z: zipfile.ZipFile):
    aliases = {}
    ambiguous = set()
    count_files = 0
    for filename in sorted(z.namelist()):
        system = match_system(filename)
        if not system or not filename.lower().endswith(".dat"):
            continue
        # XML files are large but bounded by the archive, and no XML external
        # entities or remote document URLs are followed by ElementTree.
        root = ET.fromstring(z.read(filename))
        count_files += 1
        for game in root.findall("game"):
            name = game.attrib.get("name", "")
            identity = game.attrib.get("cloneofid") or game.attrib.get("id")
            if not name or not identity or not normalize_title(name):
                continue
            normalized_title = normalize_title(name)
            normalized_key = (system, normalized_title)
            # No-Intro clone families can include distinct retail games (e.g.
            # similarly named numbered sequels). Never collapse different game
            # names based solely on cloneofid: cross-name links require review.
            title_digest = hashlib.sha1(normalized_title.encode("utf-8")).hexdigest()[:12]
            stable_id = f"nointro:{identity}:{title_digest}"
            previous = aliases.get(normalized_key)
            if previous and previous[1] != stable_id:
                ambiguous.add(normalized_key)
            else:
                aliases[normalized_key] = (name, stable_id)
    for key in ambiguous:
        aliases.pop(key, None)
    return aliases, ambiguous, count_files


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("zip_path", type=Path, help="No-Intro XML DAT ZIP file")
    ap.add_argument("--output", type=Path, help="Output TSV (stdout if omitted)")
    args = ap.parse_args()
    with zipfile.ZipFile(args.zip_path) as z:
        aliases, ambiguous, files = extract(z)
    out = io.StringIO()
    writer = csv.writer(out, delimiter="\t", lineterminator="\n")
    writer.writerow(["system", "canonical_title", "game_id"])
    for (system, _), (title, game_id) in sorted(aliases.items()):
        writer.writerow([system, title, game_id])
    data = out.getvalue()
    if args.output:
        args.output.write_text(data, encoding="utf-8")
    else:
        sys.stdout.write(data)
    print(
        f"Processed {files} DATs; wrote {len(aliases)} identity aliases; "
        f"skipped {len(ambiguous)} ambiguous normalized titles. "
        "Differently named clone members are NOT automatically merged; historical US retail eligibility remains UNVERIFIED.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
