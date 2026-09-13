# Audit Workflow

## Paths

- Games: `/media/fat/games`
- Saves: `/media/fat/saves`
- Audit output: `/media/fat/GameLibraryAudit`
- Hash database: `mister_hash_database.tsv` beside the exporter

## Startup checks

Before auditing, the exporter verifies required commands, SHA-1 support, the bundled database, its exact MiSTer-aware schema, a minimum record count, and write access to the audit directory. Failed validation prevents a normal audit from being published.

## Audit modes

**Fast Audit** is the default after the interactive timeout. It rescans the complete library but reuses cached SHA-1 values for unchanged files when the cache format is valid.

**Full Verification** recalculates hashes for eligible ROMs rather than trusting cached hashes. The implementation can use two parallel hash workers when supported.

The MiSTer console UI is ASCII-only and uses static stage lines plus periodic progress heartbeats. It intentionally avoids background carriage-return spinners because they can overlap normal console output and produce unreliable elapsed-time displays on MiSTer hardware.

## Processing

1. Discover game and save files.
2. Filter detected BIOS/support files from the game catalog.
3. Build the in-memory index from the bundled TSV database.
4. Load the incremental hash cache.
5. Classify each cataloged file by system and filename metadata.
6. Hash eligible ROM formats and perform DAT lookup.
7. On a DAT match, prefer DAT identity and canonical ROM naming over filename inference.
8. Pair saves by original basename.
9. Detect duplicate hashes, naming collisions, and expected-folder mismatches.
10. Generate reports in a staging directory and publish complete files into the audit directory.

## Hash normalization

Raw SHA-1 is always attempted first. If it misses:

- NES may retry after stripping a 16-byte iNES/NES2 container header.
- SNES/SFC/SMC may retry after stripping a 512-byte copier header only when file size strongly indicates one.
- N64 `.z64` and `.v64` rely on raw database coverage.
- Little-endian `.n64` is not transformed by the shell script.

## Cache behavior

The cache key is based on file path plus size/mtime signature. Cached SHA-1 values can survive database changes, but cached DAT metadata is reused only when the database fingerprint is unchanged. Every audit still rescans the complete library.

## Integrity metadata

The consolidated report records audit schema version, exporter version, exporter build SHA-1, audit mode, database SHA-1, metadata-layer status, file counts, self-check result, integrity verdict, apply recommendation, and integrity notes.