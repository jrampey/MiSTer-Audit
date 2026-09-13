# MiSTer FPGA Game Library Audit — Project Context

We are continuing my MiSTer FPGA project from another ChatGPT conversation. The GitHub repository `jrampey/MiSTerFPGAGameLibraryAudit` is the source of truth. Before making changes, inspect the current repository files and understand the existing implementation.

The current Game Library Audit release is **v1.2**. Do not increment the release version unless I explicitly tell you to.

## Project purpose

The project audits my complete `/media/fat/games` library. It uses hash/DAT identification, MiSTer-aware system metadata, canonical No-Intro naming, region/release classification, save pairing, duplicate detection, location auditing, safe rename proposals, Full Verification/Fast Audit modes, caching, and consolidated `MiSTer_Library_Audit.txt` reports.

The audit path must remain read-only. Renaming is handled separately through Preview / Apply / Rollback. Never automatically rename, move, or delete ROMs or saves.

## Current implementation

`Export_Game_Library.sh` is the **v1.2** auditor. Important v1.2 work includes DAT-driven canonical naming, Genesis-vs-32X classification, NES/SNES normalized-hash fallback, exporter build fingerprints, mandatory MiSTer-aware database-schema validation, and an audit integrity verdict with `SAFE TO PREVIEW` / `DO NOT APPLY` recommendations.

`Update_Game_Library.sh` is currently labeled **v1.1** and is the separate mutation path for Preview / Apply / Rollback. A known development priority is strengthening the updater's handshake with the v1.2 audit output so Apply can validate audit schema/integrity metadata rather than relying on those fields as a manual gate.

## Hash database

The bundled `mister_hash_database.tsv` contains roughly **42,259 unique SHA-1 records** and has been expanded beyond Nintendo with No-Intro data for Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes.

The current MiSTer-aware TSV schema is authoritative. We have discussed eventually replacing the TSV database with SQLite, but **do not make that migration without reviewing the architecture first**.

## GitHub Wiki

Current behavior is documented in the repository's `wiki/` directory. GitHub Actions publishes that directory to the repository's actual GitHub Wiki. The repository copy is the source of truth for wiki content; manual pages added only to the GitHub Wiki may be removed during synchronization.

The wiki currently documents the audit workflow, hash database, reports, rename workflow, safety/invariants, and MiSTer Update All installation.

## MiSTer Downloader / Update All distribution

Custom MiSTer Downloader / Update All integration is now implemented and working.

The repository publishes a generated `db.json` using `.github/workflows/build-downloader-db.yml`. The workflow uses the official MiSTer database tooling, validates the generated database with MiSTer Downloader, and commits the current `db.json` back to `main`.

The custom database deliberately distributes only these runtime files:

- `/media/fat/Scripts/Export_Game_Library.sh`
- `/media/fat/Scripts/Update_Game_Library.sh`
- `/media/fat/Scripts/mister_hash_database.tsv`

Generated reports, caches, rename history, ROMs, saves, README/project documentation, and wiki files must **not** be managed by Update All.

The database is registered on the MiSTer through the root Downloader configuration file:

```text
/media/fat/downloader.ini
```

The custom section is:

```ini
[jrampey/MiSTerFPGAGameLibraryAudit]
db_url = https://raw.githubusercontent.com/jrampey/MiSTerFPGAGameLibraryAudit/main/db.json
```

Do not modify `Scripts/update_all.sh` to register this project. A separate `/media/fat/downloader/` directory is not required for the standard configuration described above.

The distribution workflow is now:

**ChatGPT/Codex → GitHub → VS Code → MiSTer Update All**

When one of the three distributed runtime files changes on `main`, GitHub Actions regenerates and validates `db.json`. Running Update All on the MiSTer can then retrieve the current published versions.

## Safety invariants

- Auditing is read-only.
- ROM/save mutation stays in the separate Preview / Apply / Rollback workflow.
- Never automatically rename, move, or delete ROMs or saves.
- Update All distributes project software/data only; it must not manage audit output or user library content.
- Do not increment the release version unless explicitly instructed.
- Keep the separate MiSTer Health Check project logically separate and read-only by default.

## Source-of-truth rule

The project went through several intermediate builds, so do not assume an old chat artifact is newer than GitHub. Inspect the actual repository before modifying anything. GitHub is authoritative.

For broad development changes, first inspect the repository and give me a short assessment of its current state, including inconsistencies or missing pieces. Do not make broad changes until I approve the assessment. A direct request to change a specific file or feature is authorization for that specific change.
