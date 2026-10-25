#!/usr/bin/env python3
"""Offline importer regression for identity grouping; no retail dates inferred."""
import io
import tempfile
import zipfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from import_no_intro_identities import extract, match_system, normalize_title

assert normalize_title("Blast Corps (USA) (Rev 1)") == "blast corps"
assert match_system("Nintendo - Nintendo 64 (BigEndian) (20260908-030240).dat") == "N64"
assert match_system("Nintendo - Game Boy Advance (e-Reader) (20260908-030240).dat") is None

xml = """<datafile>
<game name="Test Game (Europe)" id="1"/>
<game name="Test Game (USA)" id="2" cloneofid="1"/>
<game name="Test Game (USA) (Rev 1)" id="3" cloneofid="1"/>
<game name="Regional Different Name (USA)" id="4" cloneofid="1"/>
<game name="Ambiguous (USA)" id="5"/>
<game name="Ambiguous (USA) (Rev 1)" id="6"/>
</datafile>"""
with tempfile.TemporaryDirectory() as temp:
    path = Path(temp) / "mini.zip"
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("No-Intro/Nintendo - Nintendo 64 (BigEndian) (20260908-030240).dat", xml)
    with zipfile.ZipFile(path) as z:
        aliases, ambiguous, files = extract(z)
assert files == 1
assert len(aliases) == 2
assert aliases[("N64", "test game")][1].startswith("nointro:1:")
assert aliases[("N64", "regional different name")][1].startswith("nointro:1:")
assert aliases[("N64", "test game")][1] != aliases[("N64", "regional different name")][1]
assert ("N64", "ambiguous") in ambiguous
print("No-Intro revisions group, but differently named clone families never merge automatically")
