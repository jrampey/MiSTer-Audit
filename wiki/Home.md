# MiSTer FPGA Game Library Audit Wiki

This wiki documents the behavior currently implemented in the repository. The GitHub repository is authoritative.

## Pages

- [Audit workflow](Audit-Workflow.md) — Fast Audit, Full Verification, hashing, cache behavior, and report publishing.
- [Hash database](Hash-Database.md) — bundled TSV schema, matching rules, normalized hashes, and supported systems.
- [Reports](Reports.md) — files written under `/media/fat/GameLibraryAudit` and what each contains.
- [Rename workflow](Rename-Workflow.md) — Preview, Apply, Rollback, curated destinations, and safeguards.
- [Safety and invariants](Safety-and-Invariants.md) — boundaries that protect the library.
- [Update All installation](Update-All-Installation.md) — installation and publishing through MiSTer Downloader.

## Current implementation

The current release is **v1.4**. A single unified `MiSTer_Audit.sh` runtime provides the read-only audit plus guarded Preview / Apply / Rollback tools. Development source is split across `src/audit.sh`, `src/update.sh`, and `src/main.sh`, then assembled by `tools/build_runtime.sh`.

Authoritative DAT matches provide canonical naming and ROM-type classification. Retail/Standard ROMs remain in the parent system folder; Homebrew, Unlicensed, Aftermarket, Prototype, Beta, Demo/Sample, Translation, and Hack/Modified ROMs use one shared category folder per type. These are ROM release/status categories, not gameplay genres, and there is no per-ROM folder layer.

Update All distributes exactly two files under `/media/fat/Scripts/`: `MiSTer_Audit.sh` and `mister_hash_database.tsv`.

### Original-retail completion reconciliation

Verified No-Intro ROM revisions count as ownership of the original retail title (rather than as separate missing games). The original-retail reference excludes pirate releases, Wide-Boy development software, Zelda Collection editions, and Piko Interactive later editions. Completion remains hash/DAT-based and does not infer ownership from filenames. A fresh full audit is required to refresh reported totals.
