# MiSTer ROM Library Auditor — Project Context

The GitHub repository `jrampey/MiSTer-ROM-Library-Auditor` is the source of truth. Before making changes, inspect the current repository files and understand the existing implementation.

The current release is **v1.2**. Do not increment the release version unless explicitly instructed.

## Project purpose

MiSTer ROM Library Auditor audits a complete `/media/fat/games` MiSTer FPGA ROM library. It uses hash/DAT identification, MiSTer-aware system metadata, canonical No-Intro naming, region/release classification, save pairing, duplicate detection, location auditing, safe rename proposals, Full Verification/Fast Audit modes, caching, and consolidated `MiSTer_Library_Audit.txt` reports.

The audit path must remain read-only. Renaming is handled separately through Preview / Apply / Rollback. Never automatically rename, move, or delete ROMs or saves.

## Current implementation

`Export_Game_Library.sh` is the **v1.2** auditor. Important v1.2 work includes DAT-driven canonical naming, Genesis-vs-32X classification, NES/SNES normalized-hash fallback, exporter build fingerprints, mandatory MiSTer-aware database-schema validation, and an audit integrity verdict with `SAFE TO PREVIEW` / `DO NOT APPLY` recommendations.

`Update_Game_Library.sh` is the **v1.2** companion updater and separate mutation path. It validates audit schema/version, self-check and MiSTer-aware metadata status, integrity verdict/apply recommendation, and exporter/hash-database fingerprints before Apply. Apply is blocked when the audit says `DO NOT APPLY`, when integrity is not `PASS`, or when the exporter/database has changed since the audit was generated.

## Hash database

The bundled `mister_hash_database.tsv` contains roughly **42,259 unique SHA-1 records** and has expanded No-Intro coverage for Nintendo systems, Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes.

The current MiSTer-aware TSV schema is authoritative. SQLite has been discussed, but do not make that migration without reviewing the architecture first.

## Documentation synchronization

Documentation is part of the implementation workflow. Whenever a change materially changes runtime behavior, update `README.md`, `PROJECT_CONTEXT.md`, and one or more relevant `wiki/*.md` pages in the same development pass.

`.github/workflows/documentation-consistency.yml` enforces this guardrail on pushes and pull requests to `main` when the auditor, updater, or hash database changes.

## GitHub Wiki

Current behavior is documented in the repository's `wiki/` directory. GitHub Actions publishes that directory to the repository's actual GitHub Wiki. The repository copy is the source of truth for wiki content.

## MiSTer Downloader / Update All distribution

Custom MiSTer Downloader / Update All integration is implemented. `.github/workflows/build-downloader-db.yml` generates and validates `db.json` and distributes only:

- `/media/fat/Scripts/Export_Game_Library.sh`
- `/media/fat/Scripts/Update_Game_Library.sh`
- `/media/fat/Scripts/mister_hash_database.tsv`

Generated reports, caches, rename history, ROMs, saves, README/project documentation, and wiki files must not be managed by Update All.

The Downloader identity is now `jrampey/MiSTer-ROM-Library-Auditor`. Register it in `/media/fat/downloader.ini` with:

```ini
[jrampey/MiSTer-ROM-Library-Auditor]
db_url = https://raw.githubusercontent.com/jrampey/MiSTer-ROM-Library-Auditor/main/db.json
```

Do not modify `Scripts/update_all.sh` to register this project.

The distribution workflow is:

**ChatGPT/Codex → GitHub → VS Code → MiSTer Update All**

## Safety invariants

- Auditing is read-only.
- ROM/save mutation stays in the separate Preview / Apply / Rollback workflow.
- Never automatically rename, move, or delete ROMs or saves.
- Update All distributes project software/data only; it must not manage audit output or user library content.
- Do not increment the release version unless explicitly instructed.
- Keep the separate MiSTer Health Check project logically separate and read-only by default.

## Source-of-truth rule

GitHub is authoritative. Do not assume an old chat artifact is newer than the repository.

For broad development changes, first inspect the repository and give a short assessment of its current state, including inconsistencies or missing pieces. Do not make broad changes until approved. A direct request to change a specific file or feature is authorization for that specific change.

For an authorized implementation change that materially changes documented runtime behavior, documentation synchronization is included in that authorization.