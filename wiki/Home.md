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


### Library analysis integrity (v1.4)
- Release-family CSV uses correctly escaped quoted fields and reconciles the number of distinct DAT-matched system/title families. Invalid release-family rows cause an audit FAIL and disable Apply.
- The synthetic Full Verification suite validates release-family fields, numeric counts, and totals.
- Completion reference totals are based on the filtered bundled hash database, **not** an externally certified count of original retail releases. An incomplete or outdated DAT can change the denominator.
- Unknown or unmatched ROM hashes are never assigned retail ownership solely from a filename. Review `unmatched_hashes.csv` and `needs_review.csv` and extend verified hash coverage when warranted.
- Blocking collision rows represent conflicting destinations; Apply skips them. They are not proof that physical ROM files are duplicates.


## Original-era U.S. retail curation (v1.4 architecture)
- The auditor selects one **hash/DAT-verified** retail ROM per original game identity for the preferred region. It prefers the configured parent region, then the highest recognized official revision, then a stable path tie-break. The selected copy is proposed for the system parent; other official revisions go to shared `!Revision`, and otherwise equivalent copies go to `!Alternate Retail`. This changes curation proposals, not the ROMs during audit.
- `game_identity_aliases.tsv` associates variant DAT names with stable per-platform game IDs. Columns: `system<TAB>canonical_title<TAB>game_id`. Where absent, a normalized name-based provisional ID remains, so cross-name aliases still need review.
- `historical_us_retail.tsv` contains researched eligibility overrides: `system<TAB>game_id<TAB>canonical_title<TAB>status<TAB>us_release_date<TAB>evidence_url`. Use `YES` only with an original-platform U.S. retail date and public evidence; use `NO` to exclude documented nonoriginal/non-U.S. releases (use `-` as the date placeholder). Both files are distributed to `/media/fat/Scripts/` by Update All. They ship header-only rather than claiming an unsourced historical checklist.
- A `YES`-verified World-region original release can be promoted to the parent when appropriate; unsourced World releases follow `WORLD_IN_PARENT`. `NO` entries are excluded from historical completion and from the parent curation candidate set.
- `library_completion.csv` retains the DAT-derived estimate and now separately reports independently sourced historical entries and explicitly labels provisional coverage. Until a historically complete sourced U.S. retail game manifest has been assembled for a console, **do not interpret the provisional denominator as a historically certified original retail release count**.
- `curation_preferred.csv` identifies the chosen ROM, alternate count, current folder, target parent, and historical evidence status. `disc_sets.csv` inventories disc media groups. No certified disc-based completion percentage is claimed in the absence of an original-era retail manifest and disc identity catalog.
- Preview/Apply skips individual CUE/BIN, CHD, ISO and related disc/playlist media until set-aware move logic exists; separating component files could corrupt playability. Saves can be renamed by basename in their existing save directory but are never arbitrarily moved into game-curation folders.
- Confirm the preview and any collisions before Apply. The original audit is read-only; rollback continues to operate for safe moves.

### Strict historical era evidence and diagnostic outputs
- `historical_console_eras.tsv` declares sourced `system<TAB>original_us_start<TAB>original_us_end<TAB>evidence_url` dates. A positive `historical_us_retail.tsv` decision is accepted only when its documented U.S. release date is inside that console's sourced original U.S. commercial era and `original_platform` matches `system`. Invalid historical rows force an audit FAIL and block Apply.
- The auditor records SHA-1 fingerprints for the history, alias and console-era files. Preview/Apply refuses stale audits if any of those sources changes after an audit.
- `parent_integrity.csv` explicitly lists physically misfiled DAT-verified retail or alternate ROMs. `historical_retail_review.csv` identifies all DAT-derived candidates that lack independently sourced eligibility; `system_retail_coverage.csv` includes consoles whose retail completion cannot yet be measured. These reports are advisory and preserve read-only audit behavior.
- Curated category names containing a slash are rendered as safe single folder names (for example, `!Demo-Sample`, not `!Demo/Sample`), preserving the one-shared-folder-per-type rule.
- **Historical precision warning:** These three TSV manifests deliberately ship without assumed catalog facts. Correct historical percentages require evidence-complete U.S. original-era lists, including disc media catalogs where applicable; DAT-derived completion is a provisional estimate, never silently certified.
