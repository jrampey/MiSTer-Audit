# MiSTer ROM Library Auditor — Project Context

> Folder and filename rules below describe the default INI settings. Change
> `PARENT_REGION` and other preferences in `MiSTer_Audit.ini` to customize them.

The GitHub repository `jrampey/MiSTer-Audit` is the source of truth. Before making changes, inspect the current repository files and understand the existing implementation.

The current release is **v1.4**. Do not increment the release version unless explicitly instructed.

v1.4 uses `MiSTer_Audit.ini` as a non-executable, whitelist-parsed preferences layer. `AUDIT_POLICY.conf` is migrated for legacy installations. Defaults preserve USA parent-folder organization and World-compatible retail completion; both are configurable.

## Project purpose

MiSTer ROM Library Auditor audits a complete `/media/fat/games` MiSTer FPGA ROM library. It uses hash/DAT identification, MiSTer-aware system metadata, canonical No-Intro naming, region/release classification, save pairing, duplicate detection, location auditing, safe rename proposals, Full Verification/Fast Audit modes, caching, and consolidated `MiSTer_Library_Audit.txt` reports.

The audit path must remain read-only. Renaming is handled separately through Preview / Apply / Rollback. Never automatically rename, move, or delete ROMs or saves.

## Current implementation

`MiSTer_Audit.sh` is the **v1.4** auditor. Important v1.4 work includes DAT-driven canonical naming, Genesis-vs-32X classification, NES/SNES normalized-hash fallback, exporter build fingerprints, mandatory MiSTer-aware database-schema validation, audit integrity verdicts, complete discovery accounting, and final-target collision classification.

Fast Audit is offered only when a prior `MiSTer_Library_Audit.txt`, `hash_cache.tsv`, and `discovery_snapshot.tsv` are present. On a first run or when that required prior state is missing, the selector offers only Full Verification. Fast Audit reuses valid path + size/mtime keyed SHA-1 cache entries and fingerprint-compatible DAT identification while still rescanning the complete library; Full Verification bypasses hash reuse and recalculates supported hashes.

The exporter terminal UI is ASCII-only and uses static stage lines plus periodic progress heartbeats. Do not reintroduce a background carriage-return spinner.

`MiSTer_Audit.sh` is the **v1.4** companion updater and separate mutation path. It validates audit schema/version, self-check and MiSTer-aware metadata status, integrity verdict/apply recommendation, and exporter/hash-database fingerprints before Apply. Hard integrity failures, non-collision warnings, or exporter/database fingerprint changes still block Apply. A `PASS WITH WARNINGS` audit whose only integrity note is `collision-review-required` is now eligible for safe Apply: the updater independently reproduces the exporter collision classification from `library_catalog.csv`, removes every blocking game row and its paired save rename from the mutation plan, and applies only the remaining safe rows after explicit confirmation.

## Final-target collision safety — Issue #7

Collision blocking is based on the final proposal after DAT identity is applied, not solely on the filename-parsed fallback proposal.

For every pre-DAT collision group, the exporter records whether each row received authoritative exact/normalized DAT identity and its final target filename. After all rows have been processed, the group is classified as:

- **resolved canonical DAT variants** when every row is authoritative and all final canonical targets are unique;
- **blocking collisions** when any row is unmatched/unsupported, two rows resolve to the same final target, or the group otherwise remains ambiguous.

Blocking collision rows still contribute to `COLLISIONS`, `collision-review-required`, and the audit's `DO NOT APPLY` recommendation. The updater treats that recommendation as a collision-only warning when `collision-review-required` is the sole integrity note, recomputes the exact blocking set from the catalog, writes those rows to `apply_skipped.tsv`, skips paired save renames, and continues with safe rows. Any non-collision warning remains a hard Apply block.

The updater's own duplicate/existing-target validation remains an independent safety layer, and it rebuilds the safe plan immediately before mutation.

Do not use filename-derived associative-array arithmetic for collision classification. Both exporter and updater evaluate collision grouping/counting through temporary TSV data and `awk`, preserving the Issue #6 apostrophe-bearing canonical-name regression.

## Hash database

The bundled `mister_hash_database.tsv` contains roughly **42,259 unique SHA-1 records** and has expanded No-Intro coverage for Nintendo systems, Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes.

The deterministic build tooling recognizes the current No-Intro `NEC - PC Engine - TurboGrafx-16` and `NEC - PC Engine SuperGrafx` DAT names. Production TSV replacement remains a deliberate reviewed action; validating additional source DATs does not automatically expand the shipped database.

The current MiSTer-aware TSV schema is authoritative. SQLite has been discussed, but do not make that migration without reviewing the architecture first.

## Future enhancement backlog

Closed issues may remain documented here when the current product is healthy and the remaining work is optional enhancement rather than an active defect.

- **Fast Audit deeper incrementality:** extend caching beyond SHA-1/DAT identity so unchanged files can reuse more filename classification and report-input work. Any implementation must still rescan/account for the complete library and freshly evaluate cross-file collisions, save pairing, completion, deletion/move effects, and integrity checks.
- **Release/distribution orchestration (former Issue #2):** optionally coordinate Downloader regeneration, exact tagged-runtime validation, wiki/docs publishing, and final public-state smoke testing directly within a versioned release path rather than depending on secondary push-triggered workflows.
- **No-Intro source automation (former Issue #5):** optionally automate upstream DAT/XML acquisition/refresh and review/promotion around the existing deterministic builder, source fingerprints/manifest, delta report, regression protection, and validator. Do not automatically replace the production TSV without deliberate review.

## Documentation synchronization

Whenever a change materially changes runtime behavior, update `README.md`, `PROJECT_CONTEXT.md`, and one or more relevant `wiki/*.md` pages in the same development pass. `.github/workflows/documentation-consistency.yml` enforces this guardrail.

## GitHub Wiki

Current behavior is documented in the repository's `wiki/` directory. GitHub Actions publishes that directory to the repository's actual GitHub Wiki. The repository copy is the source of truth for wiki content.

## MiSTer Downloader / Update All distribution

Custom MiSTer Downloader / Update All integration is implemented. `.github/workflows/publish-downloader.yml` generates and validates `db.json` and distributes only:

- `/media/fat/Scripts/MiSTer_Audit.sh`
- `/media/fat/Scripts/mister_hash_database.tsv`

Generated reports, caches, rename history, ROMs, saves, README/project documentation, and wiki files must not be managed by Update All.

The Downloader identity is `jrampey/MiSTer-Audit`:

```ini
[jrampey/MiSTer-Audit]
db_url = https://raw.githubusercontent.com/jrampey/MiSTer-Audit/main/db.json
```

Do not modify `Scripts/update_all.sh` to register this project.

The distribution workflow is **ChatGPT/Codex → GitHub → VS Code → MiSTer Update All**.

## Safety invariants

- Auditing is read-only.
- ROM/save mutation stays in the separate Preview / Apply / Rollback workflow.
- Blocking collision rows are never mutated; they are skipped and recorded in `apply_skipped.tsv`.
- A paired save rename is skipped whenever its game row is collision-blocked.
- Non-collision integrity warnings remain hard Apply blocks.
- Existing/duplicate mutation targets remain independent hard skips.
- Update All distributes project software/data only; it must not manage audit output or user library content.
- Do not increment the release version unless explicitly instructed.
- Keep the separate MiSTer Health Check project logically separate and read-only by default.

## Source-of-truth rule

GitHub is authoritative. Do not assume an old chat artifact is newer than the repository. A direct request to change a specific file or feature is authorization for that specific change; documentation synchronization is included when runtime behavior changes.

## v1.4 catalog accounting integrity

The exporter reads `$PLAN` through a dedicated file descriptor. Integrity enforces `TOTAL == CLASSIFIED` and `TOTAL + SKIPPED == GAME_SCAN_COUNT`. Failure adds `discovery-accounting-mismatch`, sets `FAIL`, and blocks Apply.

## Issue #6 canonical-collision regression

Real MiSTer evidence localized the 267-row catalog loss to the second source file resolving to `Super Noah's Ark 3D (USA) (Unl).sfc`. The cause was dead `FINAL_PROPOSAL_COUNTS` bookkeeping that performed Bash arithmetic through a filename-derived associative subscript. That bookkeeping was removed. Issue #7 must preserve this regression: canonical filenames, including apostrophes, are treated strictly as text.

Issue #7 records every final target, not only pre-DAT collision groups, so identical canonical targets from differently named sources remain blocking. The updater mirrors that classification when generating the Apply plan so those rows can be left untouched without preventing unrelated safe renames.

The audit-mode selector is controller-first: D-pad/arrow input selects and starts Fast Audit or Full Verification immediately, with no Enter confirmation required; keyboard 1/2 remains available and Fast Audit auto-starts after 15 seconds.

Exporter performance: file signatures are captured once during classification and reused during report/hash-cache processing; Full Verification hash jobs are generated during classification instead of rereading the plan; hot-path CSV output is assembled and written once per row.

Fast Audit v1.4 now treats cached analysis as dependency-scoped state: unchanged path+size+mtime records reuse SHA-1, normalized SHA-1, and filename classification; DAT identity is reused only while the database fingerprint matches. New/modified/deleted discovery deltas are reported explicitly, while collision, save-pairing, completion, duplicate, location, integrity, and final report state are rebuilt from the complete current library on every run. Full Verification continues to bypass ROM hash reuse.

- Fast Audit performance telemetry reports stage timings for discovery, save indexing, database/cache work, classification, report processing, publication, and total runtime; Full Verification also reports its parallel hash-pass time.

Fast Audit hot-loop cache and discovery output uses persistent file descriptors, avoiding repeated FAT file open/close operations. This is a performance-only optimization; audit results and safety semantics are unchanged.

Issue #9 Fast Audit optimization: unchanged ROMs may reuse database-fingerprint-bound DAT/classification row metadata. Full discovery remains mandatory and all library-global safety/accounting state is recomputed every run.
<!-- Documentation sync: Issue #9 Fast Audit incremental row-metadata cache repair validated by CI. -->


## Source architecture and cache ownership

Keep the MiSTer-facing distribution as one `MiSTer_Audit.sh`, but maintain modular source under `src/` and regenerate it with `tools/build_runtime.sh`. Fast Audit row metadata reuse is row-local. Database fingerprint changes invalidate DAT/classification metadata without unnecessarily invalidating unchanged-file SHA-1 reuse. Global collisions, duplicates, completion ownership, save pairing, accounting, integrity checks, and final reports are always rebuilt.

Generated runtime and modular source must preserve the complete per-ROM loop header and pass `bash -n` before publication.

Audit report-loop edits must replace the complete control-structure block, not partial `IFS`/proposal fragments.

For high-risk shell control-flow refactors, preserve a last-known-green runtime block and apply minimal semantic changes before regenerating modules.

<!-- Runtime cleanup sync: removed duplicated post-dispatch tail; no user-facing behavior change. -->

<!-- Fast Audit equivalence repair: cached DAT identity may be reused, but cheap report-facing canonical/location fields are re-derived each run so Fast and Full catalogs remain equivalent. -->

<!-- Hash cache format 8 preserves empty TSV metadata fields explicitly so unmatched ROM cache rows cannot shift columns during Fast Audit reload. -->

- Audit reports expose curated destination metadata and special-release categorization for DAT-identified ROMs. The updater may apply those authoritative destinations through Preview / Apply: Retail/Standard stays in the system parent folder, while special releases move into category subfolders. Paired saves mirror the category beneath their existing save-system folder. All normal collision, target, confirmation, manifest, and rollback safeguards remain in force.

- Library intelligence includes a read-only needs-review queue, explicit support-file classes, release-family summaries, and conservative CD/CHD/GDI/ISO inventory. Disc media must not be presented as Redump-verified unless authoritative hash metadata supports that identity.

- Runtime implementation for library intelligence was rebuilt from the last green audit baseline after CI caught malformed generated control flow.

<!-- CI repair: release-family aggregation uses a temporary summary file for portable Bash parsing. -->

- Library-intelligence reporting is isolated from the core cache/accounting tail; the core audit tail remains based on the last verified green implementation.

- Fast Audit and Full Verification are both supported. Fast Audit remains the default timed selection and reuses valid unchanged-file cache state while rebuilding global safety/report state.

- The runtime menu displays a short SHA-1 fingerprint of the deployed `MiSTer_Audit.sh`. Main-menu options 1–3 and audit-mode selection support Up/Down highlighted navigation plus Enter, with numeric shortcuts retained.

- Runtime fingerprinting hashes the deployed unified `MiSTer_Audit.sh` directly and must never publish a blank `build_sha1`; use `UNAVAILABLE` only when SHA-1 tooling is genuinely absent.

- Numeric menu shortcuts are single-key actions: pressing the displayed item number immediately starts that action without requiring Enter. Highlight navigation remains available independently.

## Distribution ownership

Update All currently distributes exactly two files under `/media/fat/Scripts/`: `MiSTer_Audit.sh` and `mister_hash_database.tsv`. `distributed-files.yml` gates publication on the synthetic regression and calls `publish-downloader.yml`; there is no separate `build-downloader-db.yml` workflow.

## CI workflow ownership

The distributed-files pipeline gates Downloader publication on the reusable Synthetic Library Test. MiSTer Runtime Compatibility owns runtime assembly/syntax/dependency checks without rerunning the synthetic regression. Publish Downloader validates syntax and the hash database, then publishes only after the distributed pipeline's synthetic gate passes. Exporter Performance may execute the synthetic workload to collect benchmark telemetry, but it is not the authoritative functional-regression gate. The obsolete one-time unmatched-policy workflow has been removed.

- Audit mode safety: Fast Audit cannot be selected or forced unless the prior audit bundle, hash cache, and discovery snapshot are all present; otherwise Full Verification is required.


- ROM type classification is canonicalized to one category per ROM: Retail/Standard, Homebrew, Unlicensed, Aftermarket, Prototype, Beta, Demo/Sample, Translation, or Hack/Modified. Legacy combined labels are invalidated from Fast Audit caches; DAT-matched report Type and curated destination use the same canonical category. Revisions remain Retail/Standard unless another special-release marker applies.
- Curated filename policy (documented across README/wiki): USA Retail/Standard ROMs remain in the parent system folder and omit the redundant USA/US/U region marker from the applied filename while preserving meaningful canonical qualifiers such as revision markers. Non-retail categories remain in their shared ROM-type subfolders and retain their canonical category/release markers (for example `(Unl)` or `(Proto)`) so special releases are visibly identifiable.

<!-- CI syntax repair: canonical ROM-type classifier regex escaping corrected; category semantics unchanged. -->

<!-- Runtime fix: trim_set is defined before clean_title_set; synthetic CI guards helper presence. -->

<!-- CI regression guard corrected to inspect the synthetic runtime copy at TEST_BIN/MiSTer_Audit.sh. -->

<!-- Menu fix: arrow-key selector now matches the actual ANSI Escape byte; CI guards against the escaped-literal regression. -->

<!-- Audit selector fix: arrow keys use a portable ESC variable and a complete ANSI sequence branch; syntax and regression checks cover the generated runtime. -->

<!-- Audit selector compatibility: Escape is matched with Bash ANSI-C $'\\e', avoiding raw ESC bytes while preserving generated-runtime syntax. -->

<!-- Audit selector hardening: Escape is detected by byte value (27), avoiding literal Escape and ANSI-C case-label encoding issues in generated/runtime files. -->

<!-- Audit selector parser fix: key-byte detection now uses od numeric output, eliminating quote-sensitive character-code syntax. -->

<!-- Audit selector simplification: non-shortcut keys are parsed directly as possible ANSI arrow sequences; no Escape literal or numeric byte conversion is required. -->

<!-- Audit selector regression: arrow-key handling uses direct ANSI sequence parsing; synthetic coverage verifies the CSI reader and avoids Escape-literal quoting. -->

<!-- CI sync: generated runtime normalized to exact builder output; no behavior or version change. -->


- Progress timing uses Bash `SECONDS` for elapsed-time display; do not derive `[MM:SS]` progress timestamps from wall-clock epoch values.


- Apply compatibility recognizes the auditor-emitted `SAFE TO PREVIEW (COLLISIONS SKIPPED)` recommendation when the verdict is `PASS WITH WARNINGS` and integrity notes are collision-only. Blocking collision rows remain skipped; other warnings still block Apply.

- Unknown-region placement: any ROM whose resolved region is `Unknown` uses curated destination `<System>/!Unknown Region`; Apply creates/moves into that bucket. This is an explicit exception to the Retail/Standard parent-folder rule. USA Retail/Standard remains in the system parent.


Curated subfolders use a leading `!` (for example `!Prototype`, `!Unlicensed`, and `!Unknown Region`) so they sort ahead of normal ROM entries in MiSTer file lists.

- Regional retail routing: authoritative DAT-identified Retail/Standard ROMs keep USA in the system parent; Japan/Europe/World/Canada/Australia/Korea/Brazil use `!<Region>` subfolders, other known regions use `!Other Regions`, and unmatched/unresolved ROMs use `!Unknown Region`. Special ROM-type categories take precedence over region.

<!-- CI synchronization: regional curated-destination regression guard updated for generalized region routing. -->

- Unknown Region safety: only hash/DAT-eligible ROMs route to `!Unknown Region`; unsupported inventory remains untouched. Unmatched eligible ROMs preserve their exact current filename until authoritative DAT identification.

- Support reporting: initialize `support_files.csv` before classification so skipped support/documentation rows are retained.


- Virtual Console routing: No-Intro-identified Virtual Console variants are categorized as `Virtual Console`, retain their canonical qualifier, and route to `<System>/!Virtual Console/` rather than the parent retail directory. Release-type routing takes precedence over geography.

<!-- CI sync: Virtual Console category runtime, regression coverage, and documentation are synchronized. -->
<!-- Virtual Console hardening: classification must inspect both canonical DAT ROM filename and canonical title; VC variants never satisfy Retail/Standard completion solely because source release metadata is generic retail. -->

- Apply safely removes empty MiSTer-Audit-managed category/region folders after file moves using empty-only directory removal; system roots, non-empty folders, and unrelated/user-created folders are never deleted.

- Runtime source integrity: the unified `MiSTer_Audit.sh` is generated from `src/audit.sh`, `src/update.sh`, and `src/main.sh`; CI verifies generated-runtime synchronization and Bash syntax before distribution.


## Configurable preferences

`/media/fat/Scripts/MiSTer_Audit.ini` is the user-editable preferences file.
The unified script creates it on first launch from the bundled template; Update All
continues to distribute the script and hash database and does not overwrite the INI.
Existing `AUDIT_POLICY.conf` completion settings are migrated on first creation.
The INI takes precedence thereafter. Missing keys use the documented defaults;
invalid regions, boolean values, or unknown keys stop the operation with an error.
The file is parsed as data and is never sourced as shell code.

The defaults preserve USA retail in the parent console folder, `!` folders for
other regions and special release types (including Virtual Console), a separate
`!World` folder, hash/DAT-based region identity, paired-save renaming, and empty-only
managed-folder cleanup. Folder organization uses shared categories, never genres or
one directory per game. Unidentified ROMs remain unknown regardless of their names.

To put European retail in the parent folder, change `PARENT_REGION=USA` to
`PARENT_REGION=Europe`. Supported values are USA, Europe, Japan, World, Canada,
Australia, Korea, and Brazil; US, EU and JP aliases are accepted. Authoritative
multi-region entries containing the selected region qualify for the parent folder.
USA retail then goes into `!USA`. Special-release classification takes priority.

Other switches in the commented INI control World-in-parent behavior, special,
other-region and unknown-region grouping, preferred-region tag removal, paired
save renaming, empty-directory cleanup, and completion eligibility. Boolean values
are `0` or `1`. `COMPLETION_REGIONS=PARENT` follows the parent region by default;
an explicit comma-separated list keeps completion scope independent. World counts
for USA/Europe/Japan completion by default, even while stored in `!World`.
Retail-only completion excludes Virtual Console and other non-retail types.
Prototype/beta/demo switches apply only when retail-only is disabled.

After editing preferences, run an audit (Fast is sufficient), review Preview, then
Apply. The audit records the effective preferences; Preview and Apply reject a
stale configuration, including a change made while the confirmation prompt is open.
Fast Audit refreshes region-dependent classifications while retaining ROM hashes.
Explicit Apply confirmation, collision checks, and rollback remain safety invariants.

Completion reporting: use canonical DAT game identity (excluding trailing parenthesized DAT qualifiers) to count one original retail title per game. Do not count later-platform reissues, kiosk/test/diagnostic/BIOS media, or multiple revisions as separate retail games. Hash/DAT identification remains authoritative.

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
