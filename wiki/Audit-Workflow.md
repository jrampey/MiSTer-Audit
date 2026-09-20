# Audit Workflow

## Paths

- Games: `/media/fat/games`
- Saves: `/media/fat/saves`
- Audit output: `/media/fat/GameLibraryAudit`
- Hash database: `mister_hash_database.tsv` beside the exporter

## Startup checks

Before auditing, the exporter verifies required commands, SHA-1 support, the bundled database, its exact MiSTer-aware schema, a minimum record count, and write access to the audit directory. Failed validation prevents a normal audit from being published.

## Audit modes

**Fast Audit** is the default after the interactive timeout. It rescans the complete library but reuses cached SHA-1 and DAT-identification data for unchanged files when the cache format and database fingerprint allow it.

**Full Verification** recalculates hashes for eligible ROMs rather than trusting cached hashes. The implementation can use two parallel hash workers when supported.

The MiSTer console UI is ASCII-only and uses static stage lines plus periodic progress heartbeats. It intentionally avoids background carriage-return spinners because they can overlap normal console output and produce unreliable elapsed-time displays on MiSTer hardware. Separator lines are emitted through safe `printf` formats so leading hyphens are never interpreted as options.

## Processing

1. Discover game and save files.
2. Filter detected BIOS/support files from the game catalog.
3. Build the in-memory index from the bundled TSV database.
4. Load the incremental hash/DAT cache.
5. Classify each cataloged file by system and filename metadata.
6. Hash eligible ROM formats and perform DAT lookup, reusing valid Fast Audit cache entries where possible.
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

## Future Fast Audit optimization

Fast Audit currently avoids the expensive hash work for unchanged ROMs, but it still repeats much of the shell-side classification and report construction required for a complete audit. A future optimization may add a second incremental layer for unchanged classification/report inputs keyed by stable file identity/signature.

That optimization must not turn Fast Audit into a partial-library audit. It must still account for every discovered file and freshly evaluate cross-file state that can change independently, including collisions, save pairing, completion, missing/deleted files, and integrity invariants. Full Verification remains the authoritative from-scratch hash pass.

## Integrity metadata

The consolidated report records audit schema version, exporter version, exporter build SHA-1, audit mode, database SHA-1, metadata-layer status, file counts, self-check result, integrity verdict, apply recommendation, and integrity notes.

The audit-mode selector is controller-first: D-pad/arrow input selects and starts Fast Audit or Full Verification immediately, with no Enter confirmation required; keyboard 1/2 remains available and Fast Audit auto-starts after 15 seconds.

Exporter performance: file signatures are captured once during classification and reused during report/hash-cache processing; Full Verification hash jobs are generated during classification instead of rereading the plan; hot-path CSV output is assembled and written once per row.

Fast Audit can reuse database-fingerprint-bound per-ROM DAT/classification metadata for unchanged files. Add/delete/change discovery remains full-library, while save pairing, duplicates, collisions, completion accounting, integrity checks, and final reports are rebuilt every run.
<!-- Documentation sync: Issue #9 Fast Audit incremental row-metadata cache repair validated by CI. -->


## Incremental cache safety

Fast Audit walks the complete library every run. Unchanged rows may reuse SHA-1 and fingerprint-bound local DAT/classification metadata. Reuse is tracked per row; global duplicate, collision, completion, save-pairing, accounting, and integrity state is recomputed. Full Verification bypasses reusable row metadata and recalculates supported hashes.

The generated runtime is syntax-checked in CI before synthetic auditing or publication.

CI syntax validation guards the generated report-loop control structure before distribution.

The current report-building control flow derives from the last CI-validated implementation with row-local cache reuse layered on top.

<!-- Runtime cleanup sync: removed duplicated post-dispatch tail; no user-facing behavior change. -->

<!-- Fast/Full equivalence: report-facing canonical and location fields are re-derived from cached DAT metadata each run. -->

<!-- Fast Audit cache format 8 explicitly preserves empty TSV metadata fields so unmatched ROM metadata remains column-stable across cache reloads. -->

## Curated destination metadata
For DAT-identified ROMs, the audit reports the MiSTer-aware expected folder plus a special-release category. Retail releases remain at the expected system folder; Homebrew, Unlicensed, Aftermarket, Prototype, Beta, Demo/Sample, Translation, and Hack/Modified releases receive a corresponding recommended category subfolder. This is reporting metadata only and does not move files automatically.

## Library intelligence
The audit produces four additional read-only reports: `needs_review.csv` for unmatched content needing identity/DAT review; `support_files.csv` for BIOS/boot ROM, firmware, diagnostic/test, utility, and miscellaneous support classification; `release_families.csv` for canonical-title release relationships; and `disc_media.csv` for CUE/BIN-set, CHD, GDI, and ISO inventory. Disc inventory is not equivalent to Redump verification and does not automatically convert, rename, or move multi-file sets.

<!-- Library intelligence runtime generation validated from the last green audit baseline. -->

<!-- CI repair: release-family aggregation uses a temporary summary file for portable Bash parsing. -->

<!-- Library-intelligence reports remain advisory and are generated without changing core audit cache/accounting behavior. -->

<!-- Audit mode restored: Fast Audit is again available alongside Full Verification. -->

## Menu navigation
The main menu shows the deployed runtime's short SHA-1 build fingerprint. Both the main 1–3 menu and the Fast/Full audit selector support Up/Down highlighted navigation and Enter to accept; numeric shortcuts remain available.


## Runtime fingerprint
The consolidated report fingerprints the deployed `MiSTer_Audit.sh` directly. `Exporter build SHA-1` and `build_sha1` must contain that digest; if SHA-1 tooling is unavailable, the explicit value `UNAVAILABLE` is emitted instead of a blank field.
