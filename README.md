# 🎮 MiSTer ROM Library Auditor

Audit, identify, organize, and safely clean up your MiSTer FPGA ROM library using No-Intro hashes and MiSTer-aware metadata.

> **Current release: v1.4**

> **v1.4:** adds configurable audit policy, including safe multi-region completion policy loading, while preserving the existing read-only audit and updater safety model.

## 🚀 First-time install on a fresh MiSTer / MiSTer Pi

If this MiSTer has **never had MiSTer ROM Library Auditor installed before**, add the project's Downloader database once. After that, normal MiSTer **Update All** runs can keep the installed runtime files current.

1. Open `/media/fat/downloader.ini` on the MiSTer SD card.
2. Add this block:

```ini
[jrampey/MiSTer-ROM-Library-Auditor]
db_url = https://raw.githubusercontent.com/jrampey/MiSTer-ROM-Library-Auditor/main/db.json
```

3. Save `downloader.ini`.
4. Run **Update All** on the MiSTer.
5. Update All installs `Export_Game_Library.sh`, `Update_Game_Library.sh`, and `mister_hash_database.tsv` under `/media/fat/Scripts/`.
6. Run `Export_Game_Library` from the MiSTer Scripts menu to create your first read-only library audit.

> **Start with the auditor.** `Export_Game_Library.sh` does not rename, move, or delete ROMs or saves. Review the generated audit before using the separate updater's Preview / Apply workflow.

**Audit → Review → Preview → Apply → Roll Back**

## Current runtime

`Export_Game_Library.sh` v1.4 is the read-only auditor. It scans `/media/fat/games`, identifies supported ROMs with the bundled MiSTer-aware hash database, proposes canonical names, audits saves/duplicates/locations, and publishes reports under `/media/fat/GameLibraryAudit`.

`Update_Game_Library.sh` v1.4 is the separate Preview / Apply / Rollback path with an enforced audit-integrity handshake. The exporter never renames, moves, or deletes ROMs or saves.

## Audit modes

- **Fast Audit** rescans the complete library while reusing valid cached hashes and cached DAT identification where possible.
- **Full Verification** recalculates supported hashes rather than relying on the cache.

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
1. Run Export_Game_Library
2. Review MiSTer_Library_Audit.txt
3. Investigate warnings and questionable proposals
4. Run Update_Game_Library
5. Preview
6. Review apply_preview.tsv and apply_skipped.tsv
7. Apply; collision-blocked rows remain untouched automatically
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
