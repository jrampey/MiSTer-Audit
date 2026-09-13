# MiSTer ROM Library Auditor — Project Context

The GitHub repository `jrampey/MiSTer-ROM-Library-Auditor` is the source of truth. Before making changes, inspect the current repository files and understand the existing implementation.

The current release is **v1.3**. Do not increment the release version unless explicitly instructed.

## Project purpose

MiSTer ROM Library Auditor audits a complete `/media/fat/games` MiSTer FPGA ROM library. It uses hash/DAT identification, MiSTer-aware system metadata, canonical No-Intro naming, region/release classification, save pairing, duplicate detection, location auditing, safe rename proposals, Full Verification/Fast Audit modes, caching, and consolidated `MiSTer_Library_Audit.txt` reports.

The audit path must remain read-only. Renaming is handled separately through Preview / Apply / Rollback. Never automatically rename, move, or delete ROMs or saves.

## Current implementation

`Export_Game_Library.sh` is the **v1.3** auditor. Important v1.3 work includes DAT-driven canonical naming, Genesis-vs-32X classification, NES/SNES normalized-hash fallback, exporter build fingerprints, mandatory MiSTer-aware database-schema validation, audit integrity verdicts, complete discovery accounting, and final-target collision classification.

The exporter terminal UI is ASCII-only and uses static stage lines plus periodic progress heartbeats. Do not reintroduce a background carriage-return spinner.

`Update_Game_Library.sh` is the **v1.3** companion updater and separate mutation path. It validates audit schema/version, self-check and MiSTer-aware metadata status, integrity verdict/apply recommendation, and exporter/hash-database fingerprints before Apply. Apply is blocked when the audit says `DO NOT APPLY`, when integrity is not `PASS`, or when the exporter/database has changed since the audit was generated.

## Final-target collision safety — Issue #7

Collision blocking is based on the final proposal after DAT identity is applied, not solely on the filename-parsed fallback proposal.

For every pre-DAT collision group, the exporter records whether each row received authoritative exact/normalized DAT identity and its final target filename. After all rows have been processed, the group is classified as:

- **resolved canonical DAT variants** when every row is authoritative and all final canonical targets are unique;
- **blocking collisions** when any row is unmatched/unsupported, two rows resolve to the same final target, or the group otherwise remains ambiguous.

Only blocking collision rows contribute to `COLLISIONS`, `collision-review-required`, and `DO NOT APPLY`. Resolved canonical variants are reported separately and do not by themselves block Preview. The updater's own duplicate/existing-target validation remains an independent safety layer.

Do not use filename-derived associative-array arithmetic for this logic. Issue #7 stores collision evidence in a temporary TSV and evaluates it with `awk`, preserving the Issue #6 apostrophe-bearing canonical-name regression.

## Hash database

The bundled `mister_hash_database.tsv` contains roughly **42,259 unique SHA-1 records** and has expanded No-Intro coverage for Nintendo systems, Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes.

The current MiSTer-aware TSV schema is authoritative. SQLite has been discussed, but do not make that migration without reviewing the architecture first.

## Documentation synchronization

Whenever a change materially changes runtime behavior, update `README.md`, `PROJECT_CONTEXT.md`, and one or more relevant `wiki/*.md` pages in the same development pass. `.github/workflows/documentation-consistency.yml` enforces this guardrail.

## GitHub Wiki

Current behavior is documented in the repository's `wiki/` directory. GitHub Actions publishes that directory to the repository's actual GitHub Wiki. The repository copy is the source of truth for wiki content.

## MiSTer Downloader / Update All distribution

Custom MiSTer Downloader / Update All integration is implemented. `.github/workflows/build-downloader-db.yml` generates and validates `db.json` and distributes only:

- `/media/fat/Scripts/Export_Game_Library.sh`
- `/media/fat/Scripts/Update_Game_Library.sh`
- `/media/fat/Scripts/mister_hash_database.tsv`

Generated reports, caches, rename history, ROMs, saves, README/project documentation, and wiki files must not be managed by Update All.

The Downloader identity is `jrampey/MiSTer-ROM-Library-Auditor`:

```ini
[jrampey/MiSTer-ROM-Library-Auditor]
db_url = https://raw.githubusercontent.com/jrampey/MiSTer-ROM-Library-Auditor/main/db.json
```

Do not modify `Scripts/update_all.sh` to register this project.

The distribution workflow is **ChatGPT/Codex → GitHub → VS Code → MiSTer Update All**.

## Safety invariants

- Auditing is read-only.
- ROM/save mutation stays in the separate Preview / Apply / Rollback workflow.
- Never automatically rename, move, or delete ROMs or saves.
- Update All distributes project software/data only; it must not manage audit output or user library content.
- Do not increment the release version unless explicitly instructed.
- Keep the separate MiSTer Health Check project logically separate and read-only by default.

## Source-of-truth rule

GitHub is authoritative. Do not assume an old chat artifact is newer than the repository. A direct request to change a specific file or feature is authorization for that specific change; documentation synchronization is included when runtime behavior changes.

## v1.3 catalog accounting integrity

The exporter reads `$PLAN` through a dedicated file descriptor. Integrity enforces `TOTAL == CLASSIFIED` and `TOTAL + SKIPPED == GAME_SCAN_COUNT`. Failure adds `discovery-accounting-mismatch`, sets `FAIL`, and blocks Apply.

## Issue #6 canonical-collision regression

Real MiSTer evidence localized the 267-row catalog loss to the second source file resolving to `Super Noah's Ark 3D (USA) (Unl).sfc`. The cause was dead `FINAL_PROPOSAL_COUNTS` bookkeeping that performed Bash arithmetic through a filename-derived associative subscript. That bookkeeping was removed. Issue #7 must preserve this regression: canonical filenames, including apostrophes, are treated strictly as text.
