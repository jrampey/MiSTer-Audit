# 🎮 MiSTer ROM Library Auditor

Audit, identify, organize, and safely clean up your MiSTer FPGA ROM library using No-Intro hashes and MiSTer-aware metadata.

> **Current release: v1.4**

> **v1.4:** adds configurable audit policy, including safe multi-region completion policy loading, while preserving the existing read-only audit and updater safety model.

## 🚀 First-time install on a fresh MiSTer / MiSTer Pi

If this MiSTer has **never had MiSTer ROM Library Auditor installed before**, add the project's Downloader database once. After that, normal MiSTer **Update All** runs can keep the installed runtime files current.

1. Open `/media/fat/downloader.ini` on the MiSTer SD card.
2. Add this block:

```ini
[jrampey/MiSTer-Audit]
db_url = https://raw.githubusercontent.com/jrampey/MiSTer-Audit/main/db.json
```

3. Save `downloader.ini`.
4. Run **Update All** on the MiSTer.
5. Update All installs `MiSTer_Audit.sh` and `mister_hash_database.tsv` under `/media/fat/Scripts/`.
6. Run `MiSTer_Audit` from the MiSTer Scripts menu and choose **Run library audit**.

> **Start with the auditor.** `MiSTer_Audit.sh` does not rename, move, or delete ROMs or saves. Review the generated audit before using the unified runtime's Preview / Apply workflow.

**Audit → Review → Preview → Apply → Roll Back**

## Current runtime

`MiSTer_Audit.sh` v1.4 is the read-only auditor. It scans `/media/fat/games`, identifies supported ROMs with the bundled MiSTer-aware hash database, proposes canonical names, audits saves/duplicates/locations, and publishes reports under `/media/fat/GameLibraryAudit`.

The same `MiSTer_Audit.sh` v1.4 runtime also provides the guarded Preview / Apply / Rollback path with an enforced audit-integrity handshake. The exporter never renames, moves, or deletes ROMs or saves.

## Audit modes

- **Fast Audit** is offered only when a prior audit bundle, hash cache, and discovery snapshot are present; it rescans the complete library while reusing valid cached state where possible.
- **Full Verification** is the only audit mode offered on a first run or when required prior Fast Audit state is missing, and it recalculates supported hashes rather than relying on the cache.

The exporter uses an ASCII-only MiSTer console UI with static stage lines and periodic progress heartbeats. Background carriage-return spinners are intentionally avoided because they can overlap normal output on MiSTer hardware.

The bundled database uses a required 13-column MiSTer-aware schema and includes Nintendo systems plus expanded No-Intro-backed coverage for Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes.

v1.4 uses DAT metadata for canonical naming and system classification when available. Raw SHA-1 is authoritative first, with conservative NES and SNES normalized-hash fallback after a raw miss.

## Reports and integrity metadata

The main review artifact is `/media/fat/GameLibraryAudit/MiSTer_Library_Audit.txt`.

The consolidated report contains `[AUDIT_METADATA]` including schema version, exporter version/build fingerprint, database fingerprint, metadata-layer status, self-check status, integrity verdict, and Apply recommendation.

### Final-target collision safety

Collision safety is evaluated after DAT identification. Filename parsing can initially make legitimate revisions look like collisions, but authoritative No-Intro identities may resolve them to distinct canonical filenames.

The exporter distinguishes:

- **canonical DAT variants resolved safely** — every row in the pre-DAT collision group has authoritative DAT identity and the final canonical targets are unique;
- **blocking collisions** — duplicate final canonical targets, unmatched/unsupported rows, or otherwise ambiguous groups.

The audit summary reports pre-DAT collision rows, safely resolved canonical DAT variant rows, and blocking collision rows separately.

Blocking collisions remain visible as `PASS WITH WARNINGS`, `DO NOT APPLY`, and `collision-review-required` in the audit so they cannot be missed. The updater now treats that exact collision-only warning as skippable rather than fatal: it independently reconstructs the exporter collision classification from `library_catalog.csv`, excludes every blocking game row from `apply_preview.tsv`, excludes any paired save rename, records the skips in `apply_skipped.tsv`, and allows unrelated safe renames to proceed.

The updater still blocks Apply for `FAIL`, any non-collision warning, exporter/database fingerprint changes, unsafe paths, existing targets, duplicate mutation targets, and unsupported CUE/BIN rename sets.

## v1.4 updater safety handshake

Before Preview or Apply, the updater validates the expected v1.4 audit contract. It verifies schema/version, startup self-check, MiSTer-aware metadata status, integrity verdict, Apply recommendation, exporter build SHA-1, and database SHA-1.

If the exporter or database changed after the audit was generated, a fresh audit is required. Apply revalidates immediately before mutation and requires typing `APPLY` exactly.

A clean `PASS` audit behaves as before. A `PASS WITH WARNINGS` audit is eligible for Apply only when its sole integrity note is `collision-review-required`; in that case, blocking collision rows are automatically skipped and left untouched. Any other warning remains a hard Apply block.

Rollback uses the latest rename manifest, requires typing `ROLLBACK` exactly, and remains available independently of the current audit handshake.

## Recommended workflow

```text
1. Run `MiSTer_Audit.sh` and choose Run library audit
2. Review `MiSTer_Library_Audit.txt`
3. Investigate warnings and questionable proposals
4. Return to `MiSTer_Audit.sh` and choose Update / Rename tools
5. Preview
6. Review `apply_preview.tsv` and `apply_skipped.tsv`
7. Apply; collision-blocked rows remain untouched automatically
8. Re-run the auditor after cleanup
```

## MiSTer Downloader / Update All

The repository publishes a validated MiSTer Downloader `db.json` that manages only the two distributed files under `/media/fat/Scripts/`.

Register the database in `/media/fat/downloader.ini` with:

```ini
[jrampey/MiSTer-Audit]
db_url = https://raw.githubusercontent.com/jrampey/MiSTer-Audit/main/db.json
```

`.github/workflows/distributed-files.yml` runs the synthetic regression gate and then calls `.github/workflows/publish-downloader.yml`, which rebuilds, validates, and publishes `db.json` when distributed files change. Reports, caches, rename history, ROMs, saves, README/project documentation, and wiki files are not managed by Update All.

### Legacy script-name migration

The Downloader database keeps the same database ID across the script rename. On the next Update All run, MiSTer Downloader installs the unified `MiSTer_Audit.sh` and treats the former `Export_Game_Library.sh` and `Update_Game_Library.sh` paths as obsolete. With MiSTer Downloader's normal `allow_delete = 1` setting, those two legacy managed files are removed automatically. If deletion has been disabled in Downloader settings, the old files are left in place.

## Documentation synchronization

Current behavior is documented in `README.md`, `PROJECT_CONTEXT.md`, and `wiki/`. The repository wiki directory is automatically published to the GitHub Wiki.

`.github/workflows/documentation-consistency.yml` guards against documentation drift. A change to the auditor, updater, or hash database must also update `README.md`, `PROJECT_CONTEXT.md`, and at least one relevant `wiki/*.md` page in the same development pass.

GitHub is the source of truth. The intended development/distribution flow is:

```text
ChatGPT / Codex → GitHub → VS Code → MiSTer Update All
```

## Future enhancements

The following are intentionally tracked as future improvements rather than active defects:

- **More aggressive Fast Audit incrementality:** extend the existing path + size/mtime hash/DAT cache so unchanged ROMs can also reuse more classification/report work, reducing shell parsing and report-generation overhead while preserving full-library collision, save-pairing, completion, and integrity checks. Full Verification remains the authoritative from-scratch hash pass.
- **Release/distribution orchestration:** further harden versioned releases so Downloader regeneration, wiki/documentation publishing, exact tagged-artifact validation, and final public-state smoke testing are coordinated without relying on secondary push-triggered workflows. This is the former Issue #2 follow-up.
- **No-Intro source automation:** optionally automate acquisition/refresh and review/promotion of upstream DAT/XML sources around the existing deterministic builder, manifest, delta report, regression protection, and validator. Production `mister_hash_database.tsv` remains deliberately reviewed rather than automatically replaced. This is the former Issue #5 follow-up.

These enhancements should preserve the current v1.4 safety model and do not by themselves require a release-version bump.

## Safety invariants

- Auditing is read-only.
- Rename proposals are review artifacts, not automatic actions.
- The updater is the only component intended to rename library files.
- Blocking collision rows and their paired save renames are never mutated.
- Collision-only warnings can be applied with those rows skipped; non-collision warnings cannot.
- Apply requires a compatible v1.4 audit plus explicit confirmation.
- Existing or duplicate targets are never overwritten.
- Unsafe disc-set renames are skipped.
- Rename history is retained for rollback.
- Runtime/user data is not managed by Update All.
- The project release remains v1.4 unless explicitly changed.

### Audit accounting integrity

The v1.4 exporter isolates report-plan input from commands executed during report generation. Audit integrity verifies that cataloged files equal classified files and that cataloged files plus intentionally skipped BIOS/support files equal files discovered. An accounting mismatch produces `FAIL` and `DO NOT APPLY`.

### Issue #6 catalog-accounting hardening

The v1.4 exporter avoids arithmetic evaluation of filename-derived associative-array subscripts during canonical proposal handling. The synthetic Full Verification regression includes the apostrophe-bearing duplicate canonical pattern that exposed Issue #6 and still requires every discovered file to be accounted for.

Issue #7 final-target duplicate detection spans the complete catalog, so differently named sources resolving to the same canonical target remain blocking. The updater mirrors that classification during plan construction and simply leaves those rows untouched while allowing unrelated safe operations to continue.

The audit-mode selector is controller-first: D-pad/arrow input selects and starts Fast Audit or Full Verification immediately, with no Enter confirmation required; keyboard 1/2 remains available and Fast Audit auto-starts after 15 seconds.

Exporter performance: file signatures are captured once during classification and reused during report/hash-cache processing; Full Verification hash jobs are generated during classification instead of rereading the plan; hot-path CSV output is assembled and written once per row.

Fast Audit v1.4 now treats cached analysis as dependency-scoped state: unchanged path+size+mtime records reuse SHA-1, normalized SHA-1, and filename classification; DAT identity is reused only while the database fingerprint matches. New/modified/deleted discovery deltas are reported explicitly, while collision, save-pairing, completion, duplicate, location, integrity, and final report state are rebuilt from the complete current library on every run. Full Verification continues to bypass ROM hash reuse.

- Fast Audit performance telemetry reports stage timings for discovery, save indexing, database/cache work, classification, report processing, publication, and total runtime; Full Verification also reports its parallel hash-pass time.

Fast Audit hot-loop cache and discovery output uses persistent file descriptors, avoiding repeated FAT file open/close operations. This is a performance-only optimization; audit results and safety semantics are unchanged.

Fast Audit also reuses database-fingerprint-bound per-ROM DAT/classification row metadata for unchanged files; global collision, duplicate, completion, save-pairing, integrity, and report state is still rebuilt every run.
<!-- Documentation sync: Issue #9 Fast Audit incremental row-metadata cache repair validated by CI. -->

<!-- Publish Update All: Issue #9 Fast Audit metadata cache -->


## Development architecture

The MiSTer distribution remains one dependency-light Bash runtime. Development source is split across `src/audit.sh`, `src/update.sh`, and `src/main.sh`; `tools/build_runtime.sh` assembles `MiSTer_Audit.sh`. Fast Audit uses row-local metadata reuse, while discovery and all global safety state are rebuilt every run.

Runtime generation now validates the complete per-ROM loop syntax before publication.

The modular runtime build preserves and CI-validates the complete audit report-loop control structure.

The report-building block is based on the last CI-validated runtime and carries only the row-local Fast Audit cache change.

<!-- Runtime cleanup sync: removed duplicated post-dispatch tail; no user-facing behavior change. -->

<!-- Fast Audit cache equivalence: cached DAT metadata is reused while report-facing canonical/location fields are re-derived for Full-equivalent output. -->

<!-- Fast Audit cache format 8 explicitly preserves empty TSV metadata fields, preventing unmatched-ROM cache columns from shifting on reload. -->

### Curated destinations and special releases
DAT-identified ROMs now expose a curated MiSTer destination derived from the MiSTer-aware expected folder. Non-retail releases are additionally categorized as Homebrew, Unlicensed, Aftermarket, Prototype, Beta, Demo/Sample, Translation, or Hack/Modified and receive a category subfolder recommendation. These fields are advisory/read-only in the audit and do not cause moves by themselves.

### Library intelligence reports
The audit now publishes `needs_review.csv` for unmatched/unknown content, `support_files.csv` for explicit BIOS/firmware/diagnostic/utility classification, `release_families.csv` for owned release relationships by canonical title, and `disc_media.csv` for CUE/CHD/GDI/ISO inventory. Disc media support is deliberately conservative: Redump-grade identification is reported only when the bundled hash metadata can identify the file; multi-file disc validation/conversion is not performed automatically.

<!-- runtime repair: library intelligence report generation rebuilt from the last green audit baseline -->

<!-- CI repair: release-family aggregation uses a temporary summary file for portable Bash parsing. -->

<!-- Runtime repair: restored the known-green audit tail while preserving advisory library-intelligence reports. -->

<!-- Audit mode restored: Fast Audit and Full Verification are both available; Fast Audit remains the default timed selection. -->

### Runtime menu navigation
The unified runtime displays its short SHA-1 build fingerprint in the main menu. The main 1–3 menu and the Fast/Full audit-mode menu support Up/Down highlight navigation with Enter to accept, while retaining numeric shortcuts.


### Runtime fingerprint reliability
The audit records the SHA-1 of the deployed unified `MiSTer_Audit.sh` directly. If no SHA-1 implementation is available it reports `UNAVAILABLE` rather than publishing a blank build fingerprint; the updater therefore receives an explicit build identity for its safety handshake.


### Immediate numeric menu shortcuts
Number keys execute their corresponding menu action immediately; pressing Enter after a numeric shortcut is not required. Arrow-key highlighting and Enter-to-accept remain available where supported.


### Curated special-release destinations

For authoritative DAT-identified special releases, Preview/Apply uses the audit's `curated_destination` metadata as the game target directory. `Retail/Standard` releases remain in the existing system parent folder; Homebrew, Unlicensed, Aftermarket, Prototype, Beta, Demo/Sample, Translation, and Hack/Modified releases are routed into matching category subfolders. Paired saves follow the same category beneath their existing save-system folder. Preview, collision checks, existing-target protection, explicit APPLY confirmation, manifests, and Rollback still apply.



- ROM type classification is canonicalized to one category per ROM: Retail/Standard, Homebrew, Unlicensed, Aftermarket, Prototype, Beta, Demo/Sample, Translation, or Hack/Modified. Legacy combined labels are invalidated from Fast Audit caches; DAT-matched report Type and curated destination use the same canonical category. Revisions remain Retail/Standard unless another special-release marker applies.

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


### Curated filename policy

USA Retail/Standard ROMs stay in the parent system folder and use clean canonical filenames without the redundant `(USA)`, `(US)`, or `(U)` region marker. Meaningful canonical qualifiers such as revisions remain. Non-retail ROM types stay in their shared category subfolders and retain canonical identifying markers such as `(Unl)` and `(Proto)`.

<!-- CI sync: generated runtime normalized to exact builder output; curated filename behavior remains unchanged. -->


<!-- Progress timing: elapsed audit progress uses Bash SECONDS (monotonic within the process) so MiSTer clock/epoch state cannot produce bogus multi-million-minute timestamps. -->


<!-- Apply compatibility: PASS WITH WARNINGS + SAFE TO PREVIEW (COLLISIONS SKIPPED) is eligible for Apply only when integrity notes are collision-only; blocking collision rows remain skipped. -->


### Unknown-region placement
ROMs whose region remains `Unknown` are assigned to `<System>/!Unknown Region` instead of the system parent directory. Apply creates that folder as needed. USA Retail/Standard ROMs continue to remain directly in the system parent folder; known-region special releases continue to use their ROM-type category folders.


Curated subfolders use a leading `!` (for example `!Prototype`, `!Unlicensed`, and `!Unknown Region`) so they sort ahead of normal ROM entries in MiSTer file lists.


### Regional retail placement
DAT-identified Retail/Standard ROMs use authoritative No-Intro region metadata for placement. USA retail remains in the system parent folder. Japan, Europe, World, Canada, Australia, Korea, and Brazil retail releases use matching `!<Region>` subfolders; other known regions use `!Other Regions`. ROMs without an authoritative DAT identity remain in `!Unknown Region`. Special release categories take precedence over geography and continue to use their `!Prototype`, `!Unlicensed`, and other ROM-type folders.

<!-- Regional routing runtime synchronization validated after generated-runtime rebuild. -->

<!-- CI synchronization: regional curated-destination regression guard updated for generalized region routing. -->


### Unknown Region safety
Only hash/DAT-eligible ROMs participate in regional Unknown routing. Unsupported inventory such as documentation, disc media, and machine/support files remains in place and receives no regional rename. An unmatched eligible ROM may be placed in `!Unknown Region`, but its exact current filename is preserved until authoritative DAT identification is available.


Support-file rows are initialized before classification so skipped documentation and support files remain present in `support_files.csv`.


### Virtual Console releases
No-Intro-identified Virtual Console ROM images are treated as a distinct `Virtual Console` release category rather than ordinary Retail/Standard originals. They retain their canonical Virtual Console qualifier and route to `<System>/!Virtual Console/`, keeping the parent system directory representative of original-system retail releases. This includes canonical labels such as Wii U Virtual Console and combined Virtual Console/Switch Online releases.

<!-- CI sync: Virtual Console category runtime, regression coverage, and documentation are synchronized. -->
