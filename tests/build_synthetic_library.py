#!/usr/bin/env python3
"""Build a deterministic MiSTer-shaped synthetic library for integration tests."""
from pathlib import Path
import argparse

CANDIDATES = 6469
SKIPPED = 106
SYSTEMS = [
    ("NES", ".nes", 120),
    ("SNES", ".sfc", 120),
    ("GBA", ".gba", 120),
    ("MegaDrive", ".md", 120),
    ("N64", ".z64", 120),
    ("TGFX16", ".pce", 120),
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default="/media/fat")
    args = parser.parse_args()
    root = Path(args.root)
    games = root / "games"
    saves = root / "saves"
    games.mkdir(parents=True, exist_ok=True)
    saves.mkdir(parents=True, exist_ok=True)

    created = 0
    for system, ext, count in SYSTEMS:
        folder = games / system
        folder.mkdir(parents=True, exist_ok=True)
        for i in range(count):
            # Unique bytes exercise real Full Verification hashing without ROM data.
            (folder / f"Synthetic {system} {i:04d} (USA){ext}").write_bytes(
                f"synthetic:{system}:{i}\n".encode()
            )
            created += 1

    # The bulk profile uses an intentionally unsupported hash extension that is
    # still part of exporter discovery. This keeps the 6,575-file regression
    # test fast while exercising the same classification/report accounting path.
    bulk = games / "GameGear"
    bulk.mkdir(parents=True, exist_ok=True)
    for i in range(CANDIDATES - created):
        (bulk / f"Synthetic GameGear {i:05d} (USA).gg").write_bytes(b"")

    bios = games / "NES" / "BIOS"
    bios.mkdir(parents=True, exist_ok=True)
    for i in range(SKIPPED):
        (bios / f"support-{i:03d}.rom").write_bytes(b"synthetic support\n")

    # Save pairing coverage without bloating the fixture.
    save_folder = saves / "NES"
    save_folder.mkdir(parents=True, exist_ok=True)
    for i in range(25):
        (save_folder / f"Synthetic NES {i:04d} (USA).sav").write_bytes(b"save\n")

    print(f"Synthetic library built: {CANDIDATES + SKIPPED} discovered, "
          f"{CANDIDATES} candidates, {SKIPPED} support files")


if __name__ == "__main__":
    main()
