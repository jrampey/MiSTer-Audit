# 🎮 MiSTer ROM Library Auditor

Audit, identify, organize, and safely clean up your MiSTer FPGA ROM library using No-Intro hashes and MiSTer-aware metadata.

> **Current release: v1.3**

**Audit → Review → Preview → Apply → Roll Back**

## Current runtime

`Export_Game_Library.sh` v1.3 is the read-only auditor. It scans `/media/fat/games`, identifies supported ROMs with the bundled MiSTer-aware hash database, proposes canonical names, audits saves/duplicates/locations, and publishes reports under `/media/fat/GameLibraryAudit`.

`Update_Game_Library.sh` v1.3 is the separate Preview / Apply / Rollback path with an enforced audit-integrity handshake.

Runtime files are installed together under `/media/fat/Scripts/`: `Export_Game_Library.sh`, `Update_Game_Library.sh`, and `mister_hash_database.tsv`.

The exporter never renames, moves, or deletes ROMs or saves.

## Audit modes

- **Fast Audit** rescans the complete library while reusing valid cached hashes where possible.
- **Full Verification** recalculates supported hashes rather than relying on the cache.

The bundled database uses a required 13-column MiSTer-aware schema and includes Nintendo systems plus expanded No-Intro-backed coverage for Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes.

v1.3 uses DAT metadata for canonical naming and system classification when available. Raw SHA-1 is authoritative first, with conservative NES and SNES normalized-hash fallback after a raw miss.

## Reports and integrity metadata

The main review artifact is `/media/fat/GameLibraryAudit/MiSTer_Library_Audit.txt`.

The consolidated report contains `[AUDIT_METADATA]` including schema version, exporter version/build fingerprint, database fingerprint, metadata-layer status, self-check status, integrity verdict, and Apply recommendation.

## v1.3 updater safety handshake

Before Preview or Apply, the updater validates the expected v1.3 audit contract. It verifies schema/version, startup self-check, MiSTer-aware metadata status, integrity verdict, Apply recommendation, exporter build SHA-1, and database SHA-1.

If the exporter or database changed after the audit was generated, a fresh audit is required. Apply requires a fully passing audit, revalidates immediately before mutation, and requires typing `APPLY` exactly. `DO NOT APPLY` is enforced by the updater.

Rollback uses the latest rename manifest, requires typing `ROLLBACK` exactly, and remains available independently of the current audit handshake.

## Recommended workflow

```text
1. Run Export_Game_Library
2. Review MiSTer_Library_Audit.txt
3. Investigate warnings and questionable proposals
4. Run Update_Game_Library
5. Preview
6. Review planned and skipped operations
7. Apply only when the v1.3 integrity checks pass
8. Re-run the auditor after cleanup
```

## MiSTer Downloader / Update All

The repository publishes a validated MiSTer Downloader `db.json` that manages only the three runtime files under `/media/fat/Scripts/`.

Register the database in `/media/fat/downloader.ini` with:

```ini
[jrampey/MiSTer-ROM-Library-Auditor]
db_url = https://raw.githubusercontent.com/jrampey/MiSTer-ROM-Library-Auditor/main/db.json
```

`.github/workflows/build-downloader-db.yml` rebuilds and validates `db.json` when a distributed runtime file or the distribution workflow changes. Reports, caches, rename history, ROMs, saves, README/project documentation, and wiki files are not managed by Update All.

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
- Apply requires a compatible passing v1.3 audit plus explicit confirmation.
- Existing or duplicate targets are never overwritten.
- Unsafe disc-set renames are skipped.
- Rename history is retained for rollback.
- Runtime/user data is not managed by Update All.
- The project release remains v1.3 unless explicitly changed.

See `wiki/` for detailed current behavior and `PROJECT_CONTEXT.md` for development constraints and project context.