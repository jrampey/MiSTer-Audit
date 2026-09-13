#!/usr/bin/env python3
"""Validate a No-Intro ZIP against the current library catalog without mutating the ROM library."""
from __future__ import annotations
import argparse, csv, re, zipfile
import xml.etree.ElementTree as ET

RULES = [
    ("Nintendo - Nintendo Entertainment System", "NES"),
    ("Nintendo - Family Computer Disk System", "NES"),
    ("Nintendo - Super Nintendo Entertainment System", "SNES"),
    ("Nintendo - Nintendo 64", "N64"),
    ("Nintendo - Game Boy Color", "GBC"),
    ("Nintendo - Game Boy Advance", "GBA"),
    ("Nintendo - Game Boy", "GAMEBOY"),
    ("Sega - Mega Drive - Genesis", "Genesis"),
    ("Sega - 32X", "S32X"),
    ("Sega - Master System - Mark III", "SMS"),
    ("Atari - Atari 2600", "Atari2600"),
    ("Mattel - Intellivision", "Intellivision"),
    ("NEC - PC Engine - TurboGrafx-16", "TGFX16"),
    ("NEC - PC Engine SuperGrafx", "TGFX16"),
    ("Commodore - Amiga", "Amiga"),
    ("Commodore - Commodore 64", "C64"),
    ("Acorn - Archimedes", "ARCHIE"),
]

def map_system(name: str):
    low = name.lower()
    for needle, system in RULES:
        if needle.lower() in low:
            return system
    return None

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("zip")
    ap.add_argument("catalog")
    args=ap.parse_args()
    hashes={}
    dat_count=0
    with zipfile.ZipFile(args.zip) as z:
        for member in z.namelist():
            if not member.lower().endswith((".dat", ".xml")):
                continue
            root=ET.fromstring(z.read(member))
            header=root.find("header")
            name=(header.findtext("name") if header is not None else None) or member
            system=map_system(name)
            if not system:
                continue
            dat_count += 1
            hashes.setdefault(system,set())
            for game in root.findall("game"):
                for rom in game.findall("rom"):
                    sha=(rom.get("sha1") or "").lower().strip()
                    if re.fullmatch(r"[0-9a-f]{40}",sha): hashes[system].add(sha)
    unmatched=[]
    with open(args.catalog,encoding="utf-8-sig",newline="") as f:
        for row in csv.DictReader(f):
            if row.get("system")=="NES" and row.get("dat_match")=="No match": unmatched.append(row)
    direct=[r for r in unmatched if r.get("sha1","").lower() in hashes.get("NES",set())]
    print(f"recognized_dats={dat_count}")
    for system in sorted(hashes): print(f"{system}={len(hashes[system])}")
    print(f"nes_unmatched={len(unmatched)}")
    print(f"nes_additional_direct_matches={len(direct)}")
    for row in direct: print(row.get("original_filename", ""))

if __name__ == "__main__": main()
