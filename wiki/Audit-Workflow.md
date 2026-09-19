# Audit Workflow

## Paths

- Games: `/media/fat/games`
- Saves: `/media/fat/saves`
- Audit output: `/media/fat/GameLibraryAudit`
- Hash database: `mister_hash_database.tsv` beside the exporter

## Startup checks

Before auditing, the exporter verifies required commands, SHA-1 support, the bundled database, its exact MiSTer-aware schema, a minimum record count, and write access to the audit directory. Failed validation prevents a normal audit from being published.

## Audit modes

**Full Verification** is the standard and only audit mode. It rescans the complete library and recalculates hashes for eligible ROMs. The implementation can use two parallel hash workers when supported.

The MiSTer console UI is ASCII-only and uses static stage lines plus periodic progress heartbeats. It intentionally avoids background carriage-return spinners because they can overlap normal console output and produce unreliable elapsed-time displays on MiSTer hardware. Separator lines are emitted through safe `printf` formats so leading hyphens are never interpreted as options.

## Processing

1. Discover game and save files.
2. Filter detected BIOS/support files from the game catalog.
3. Build the in-memory index from the bundled TSV database.
4. Load the incremental hash/DAT cache.
5. Classify each cataloged file by system and filename metadata.
6. Hash eligible ROM formats from scratch and perform DAT lookup.
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

The cache key is based on file path plus size/mtime signature. Cached SHA-1 values can survive database changes, but cached DAT metadata is reused only when the database fingerprint is unchanged. Every audit still rescans the complete library so collision, save-pairing, completion, and integrity checks remain current.


## Integrity metadata

The consolidated report records audit schema version, exporter version, exporter build SHA-1, audit mode, database SHA-1, metadata-layer status, file counts, self-check result, integrity verdict, apply recommendation, and integrity notes.


Exporter performance: file signatures are captured once during classification and reused during report/hash-cache processing; Full Verification hash jobs are generated during classification instead of rereading the plan; hot-path CSV output is assembled and written once per row.



## Incremental cache safety

Every audit uses Full Verification, with complete discovery, supported-file hashing, and fresh global duplicate, collision, completion, save-pairing, accounting, integrity, and report state.

The generated runtime is syntax-checked in CI before synthetic auditing or publication.

CI syntax validation guards the generated report-loop control structure before distribution.

The current report-building control flow derives from the last CI-validated implementation with row-local cache reuse layered on top.

<!-- Runtime cleanup sync: removed duplicated post-dispatch tail; no user-facing behavior change. -->



## Curated destination metadata
For DAT-identified ROMs, the audit reports the MiSTer-aware expected folder plus a special-release category. Retail releases remain at the expected system folder; Homebrew, Unlicensed, Aftermarket, Prototype, Beta, Demo/Sample, Translation, and Hack/Modified releases receive a corresponding recommended category subfolder. This is reporting metadata only and does not move files automatically.

## Library intelligence
The audit produces four additional read-only reports: `needs_review.csv` for unmatched content needing identity/DAT review; `support_files.csv` for BIOS/boot ROM, firmware, diagnostic/test, utility, and miscellaneous support classification; `release_families.csv` for canonical-title release relationships; and `disc_media.csv` for CUE/BIN-set, CHD, GDI, and ISO inventory. Disc inventory is not equivalent to Redump verification and does not automatically convert, rename, or move multi-file sets.

<!-- Library intelligence runtime generation validated from the last green audit baseline. -->

<!-- CI repair: release-family aggregation uses a temporary summary file for portable Bash parsing. -->

<!-- Library-intelligence reports remain advisory and are generated without changing core audit cache/accounting behavior. -->
