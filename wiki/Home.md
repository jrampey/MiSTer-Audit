# MiSTer FPGA Game Library Audit Wiki

This wiki documents the behavior currently implemented in the repository. It describes what the scripts do today; planned work belongs in `PROJECT_CONTEXT.md` or future development notes.

## Pages

- [Audit workflow](Audit-Workflow.md) — Fast Audit, Full Verification, hashing, cache behavior, and report publishing.
- [Hash database](Hash-Database.md) — bundled TSV schema, matching rules, normalized hashes, and supported systems.
- [Reports](Reports.md) — files written under `/media/fat/GameLibraryAudit` and what each contains.
- [Rename workflow](Rename-Workflow.md) — Preview, Apply, Rollback, safeguards, and current limitations.
- [Safety and invariants](Safety-and-Invariants.md) — read-only boundaries and rules that protect the library.
- [Update All installation](Update-All-Installation.md) — add this repository to MiSTer Downloader / Update All and keep the runtime files current.

## Current implementation

The auditor is **v1.2**. `MiSTer-Audit-Export.sh` scans `/media/fat/games`, optionally hashes DAT-eligible ROMs, identifies matches using the bundled MiSTer-aware hash database, pairs saves, detects duplicates and location issues, proposes canonical renames, and publishes a consolidated audit.

`MiSTer-Audit-Update.sh` is currently labeled **v1.1**. It is the separate mutation path for previewing, applying, and rolling back rename proposals.

The repository also publishes a MiSTer Downloader-compatible `db.json`. GitHub Actions regenerates and validates this database whenever one of the distributed runtime files changes. The database installs only `MiSTer-Audit-Export.sh`, `MiSTer-Audit-Update.sh`, and `mister_hash_database.tsv` into `/media/fat/Scripts/`.

The repository's implementation is authoritative. This wiki should be updated when behavior changes.