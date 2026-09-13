#!/usr/bin/env python3
"""Extract MiSTer-relevant DAT/XML files from a No-Intro ZIP, then run the normal database builder."""
from __future__ import annotations
import argparse, pathlib, shutil, subprocess, tempfile, zipfile
from validate_full_nointro_zip import RULES, map_system
import xml.etree.ElementTree as ET

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("zip")
    ap.add_argument("--database",default="mister_hash_database.tsv")
    ap.add_argument("--manifest",default="Sources/no_intro_manifest.json")
    ap.add_argument("--delta",default="build/hash_database_delta.md")
    args=ap.parse_args()
    with tempfile.TemporaryDirectory(prefix="nointro-") as td:
        root=pathlib.Path(td)
        count=0
        with zipfile.ZipFile(args.zip) as z:
            for member in z.namelist():
                if not member.lower().endswith((".dat",".xml")): continue
                data=z.read(member)
                xml=ET.fromstring(data)
                header=xml.find("header")
                name=(header.findtext("name") if header is not None else None) or member
                if not map_system(name): continue
                out=root/pathlib.Path(member).name
                out.write_bytes(data)
                count += 1
        if not count: raise SystemExit("No supported MiSTer-relevant DAT/XML files found")
        cmd=["python3","tools/build_hash_database.py","--sources",str(root),"--database",args.database,"--manifest",args.manifest,"--delta",args.delta]
        print(f"Extracted {count} supported DAT/XML files")
        raise SystemExit(subprocess.call(cmd))

if __name__ == "__main__": main()
