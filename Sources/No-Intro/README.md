# No-Intro source DATs

Drop current No-Intro `.dat` or `.xml` files anywhere under this directory and run:

```bash
python3 tools/build_hash_database.py
python3 tools/validate_hash_database.py mister_hash_database.tsv --min-records 40000
```

The builder fingerprints each recognized source with SHA-256, records provenance in `Sources/no_intro_manifest.json`, replaces only the MiSTer systems represented by the supplied DATs, preserves other existing systems, writes a deterministic `mister_hash_database.tsv`, and produces `build/hash_database_delta.md`.

You do not need to rename the original No-Intro files. System detection uses the DAT header name, not the timestamped filename.

Recognized families currently include NES/FDS, SNES, N64, Game Boy, Game Boy Color, Game Boy Advance, Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, Commodore 64, and Archimedes.

For systems with multiple representations, keep all desired DATs in this directory at the same time. For example, NES Headered and Headerless DATs can both contribute hashes to the NES records.

A per-system record drop greater than 10% blocks replacement by default. Investigate the source set rather than overriding the guard unless the reduction is intentional.

These DATs are build-time inputs only. They are not distributed to MiSTer by Update All, and the MiSTer exporter does not parse or download them.
