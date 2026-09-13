# 🎮 MiSTer FPGA Game Library Audit

A read-only-first toolkit for auditing, identifying, and safely cleaning up a MiSTer FPGA game library.

> **Current release: v1.2**

**Audit → Review → Preview → Apply → Roll Back**

## Current runtime

`Export_Game_Library.sh` v1.2 is the read-only auditor. It scans `/media/fat/games`, identifies supported ROMs with the bundled MiSTer-aware hash database, proposes canonical names, audits saves/duplicates/locations, and publishes reports under `/media/fat/GameLibraryAudit`.

`Update_Game_Library.sh` v1.2 is the separate Preview / Apply / Rollback path. The previous v1.1 updater mismatch has been resolved.

Runtime files are installed together under `/media/fat/Scripts/`:

- `Export_Game_Library.sh`
- `Update_Game_Library.sh`
- `mister_hash_database.tsv`

The exporter never renames, moves, or deletes ROMs or saves.

## Audit modes

- **Fast Audit** rescans the complete library while reusing valid cached hashes where possible.
- **Full Verification** recalculates supported hashes rather than relying on the cache.

The bundled database uses a required 13-column MiSTer-aware schema and includes Nintendo systems plus expanded No-Intro-backed coverage for Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes.

v1.2 uses DAT metadata for canonical naming and system classification when available. Raw SHA-1 is authoritative first, with conservative NES and SNES normalized-hash fallback after a raw miss.

## Reports and integrity metadata

The main review artifact is:

`/media/fat/GameLibraryAudit/MiSTer_Library_Audit.txt`

The audit also publishes structured catalog, rename proposal, save proposal, DAT match/unmatched, duplicate-hash, location-audit, and cache files.

The consolidated report contains `[AUDIT_METADATA]` including schema version, exporter version/build fingerprint, database fingerprint, metadata-layer status, self-check status, integrity verdict, and Apply recommendation.

## v1.2 updater safety handshake

Before Preview or Apply, the updater validates that the proposal set came from the expected v1.2 audit contract. It verifies:

- audit schema version `4`;
- exporter version `1.2`;
- startup self-check passed;
- MiSTer-aware metadata layer is valid;
- integrity verdict and Apply recommendation are recognized;
- the installed exporter matches the audit's exporter SHA-1; and
- the installed hash database matches the audit's database SHA-1.

If the exporter or database changed after the audit was generated, a fresh audit is required.

Preview remains a review operation. Apply requires a fully passing audit and an Apply recommendation that permits proceeding. `DO NOT APPLY` is enforced by the updater.

Apply revalidates the handshake immediately before file mutation and requires typing `APPLY` exactly. Existing destinations, duplicate targets, unsafe names, out-of-root paths, missing sources, and unsupported CUE renames remain blocked or skipped.

Rollback uses the latest rename manifest, requires typing `ROLLBACK` exactly, and remains available independently of the current audit handshake so recovery is possible after software/database changes.

## Recommended workflow

```text
1. Run Export_Game_Library
2. Review MiSTer_Library_Audit.txt
3. Investigate warnings and questionable proposals
4. Run Update_Game_Library
5. Preview
6. Review planned and skipped operations
7. Apply only when the v1.2 integrity checks pass
8. Re-run the auditor after cleanup
```

## MiSTer Downloader / Update All

The repository publishes a validated MiSTer Downloader `db.json` that manages only the three runtime files under `/media/fat/Scripts/`.

Register the database in `/media/fat/downloader.ini` with:

```ini
[jrampey/MiSTerFPGAGameLibraryAudit]
db_url = https://raw.githubusercontent.com/jrampey/MiSTerFPGAGameLibraryAudit/main/db.json
```

`.github/workflows/build-downloader-db.yml` rebuilds and validates `db.json` when a distributed runtime file changes. Reports, caches, rename history, ROMs, saves, README/project documentation, and wiki files are not managed by Update All.

## Documentation synchronization

Current behavior is documented in `README.md`, `PROJECT_CONTEXT.md`, and `wiki/`. The repository wiki directory is automatically published to the GitHub Wiki.

`.github/workflows/documentation-consistency.yml` guards against documentation drift. A change to the auditor, updater, or hash database must also update `README.md`, `PROJECT_CONTEXT.md`, and at least one relevant `wiki/*.md` page in the same change set.

GitHub is the source of truth. The intended development/distribution flow is:

```text
ChatGPT / Codex → GitHub → VS Code → MiSTer Update All
```

## Safety invariants

- Auditing is read-only.
- Rename proposals are review artifacts, not automatic actions.
- The updater is the only component intended to rename library files.
- Apply requires a compatible passing v1.2 audit plus explicit confirmation.
- Existing or duplicate targets are never overwritten.
- Unsafe disc-set renames are skipped.
- Rename history is retained for rollback.
- Runtime/user data is not managed by Update All.
- The project release remains v1.2 unless explicitly changed.

See `wiki/` for detailed current behavior and `PROJECT_CONTEXT.md` for development constraints and project context.