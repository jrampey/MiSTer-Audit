# MiSTer FPGA Game Library Audit Wiki

This wiki documents the behavior currently implemented in the repository. It describes what the scripts do today; planned work belongs in `PROJECT_CONTEXT.md` or future development notes.

## Pages

- [Audit workflow](Audit-Workflow.md) — Fast Audit, Full Verification, hashing, cache behavior, and report publishing.
- [Hash database](Hash-Database.md) — bundled TSV schema, matching rules, normalized hashes, and supported systems.
- [Reports](Reports.md) — files written under `/media/fat/GameLibraryAudit` and what each contains.
- [Rename workflow](Rename-Workflow.md) — Preview, Apply, Rollback, safeguards, and current limitations.
- [Safety and invariants](Safety-and-Invariants.md) — read-only boundaries and rules that protect the library.

## Current implementation

The auditor is **v1.2**. `Export_Game_Library.sh` scans `/media/fat/games`, optionally hashes DAT-eligible ROMs, identifies matches using the bundled MiSTer-aware hash database, pairs saves, detects duplicates and location issues, proposes canonical renames, and publishes a consolidated audit.

`Update_Game_Library.sh` is currently labeled **v1.1**. It is the separate mutation path for previewing, applying, and rolling back rename proposals.

The repository's implementation is authoritative. This wiki should be updated when behavior changes.