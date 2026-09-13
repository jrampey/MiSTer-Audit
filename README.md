# 🎮 MiSTer FPGA Game Library Audit

A read-only-first toolkit for auditing, identifying, and safely cleaning up a MiSTer FPGA game library.

> **Current auditor release: v1.2**

**Audit → Review → Preview → Apply → Roll Back**

The core rule is simple:

> 🛡️ **Identify first, preview second, modify last.**

## What it does

`Export_Game_Library.sh` scans `/media/fat/games` without modifying ROMs or saves. It builds a complete catalog, identifies supported ROMs by SHA-1 against the bundled MiSTer-aware database, proposes canonical names, checks save pairing and locations, detects duplicates and collisions, and publishes detailed reports under `/media/fat/GameLibraryAudit`.

`Update_Game_Library.sh` is deliberately separate. It can preview approved rename proposals, apply safety-checked filename changes, and roll back the last applied cleanup.

## Files

Place the runtime files together on the MiSTer, normally under `/media/fat/Scripts/`:

```text
/media/fat/Scripts/
├── Export_Game_Library.sh
├── Update_Game_Library.sh
└── mister_hash_database.tsv
```

| File | Purpose |
| --- | --- |
| `Export_Game_Library.sh` | v1.2 read-only auditor and report generator |
| `Update_Game_Library.sh` | Preview / Apply / Rollback rename tool; currently labeled v1.1 |
| `mister_hash_database.tsv` | Bundled SHA-1 database with canonical and MiSTer-aware metadata |

Original DAT files are not required on the MiSTer. The exporter reads the bundled TSV directly.

## Running an audit

Run `Export_Game_Library` from the MiSTer Scripts menu. At startup the exporter performs safety/self-checks, including validating the bundled database's required MiSTer-aware schema.

Two audit modes are available:

- **Fast Audit** — default. Rescans the full library but reuses cached SHA-1 values for unchanged files when possible.
- **Full Verification** — recalculates hashes for DAT-eligible ROMs instead of relying on cached hashes. Hash work can run in parallel when the MiSTer environment supports it.

The cache is an optimization only. Fast Audit still rediscovers and re-evaluates the library on every run.

During the audit, the exporter:

- inventories the game library and filters detected BIOS/support files;
- determines DAT/hash eligibility by system and extension;
- calculates or reuses SHA-1 hashes;
- matches hashes against `mister_hash_database.tsv`;
- uses DAT metadata for canonical title, ROM name, system, core, expected folder, region, release type, and license status when available;
- falls back to filename-derived classification when authoritative metadata is unavailable;
- detects duplicate hashes, rename collisions, and location mismatches;
- pairs saves by the original game basename;
- generates game and save rename proposals for review; and
- publishes a consolidated audit plus machine-readable reports.

> **The exporter never renames, moves, or deletes ROMs or saves.**

## Hash identification

Raw SHA-1 is always attempted first. v1.2 also includes conservative normalized-hash fallbacks for known cartridge-container cases:

- **NES** — after a raw miss, a 16-byte iNES/NES2 header may be excluded for a second lookup.
- **SNES/SFC** — when file size indicates a 512-byte copier header, the exporter may try the payload hash after the raw miss.
- **N64 `.z64` / `.v64`** — raw database coverage is used.
- **N64 `.n64`** — the exporter does not perform a lossy shell byte-order conversion; unmatched files remain unmatched unless a raw record exists.

An unmatched hash does not automatically mean a ROM is bad. Modified dumps, patches, hacks, translations, unsupported representations, and formats outside database coverage can all be legitimate.

### Current database coverage

The bundled database is no longer Nintendo-only. Current audit logic supports MiSTer-aware hash matching for Nintendo systems plus expanded No-Intro-backed coverage including:

- NES / FDS, SNES, Game Boy, Game Boy Color, Game Boy Advance, Nintendo 64
- Genesis / Mega Drive and 32X
- Master System
- Atari 2600
- Intellivision
- PC Engine / TurboGrafx-16 and SuperGrafx
- Amiga
- Commodore 64
- Archimedes

The database uses a required 13-column schema:

```text
sha1
canonical_title
canonical_rom_name
dat_source
size
crc32
md5
mister_system
mister_core
expected_folder
region
release_type
license_status
```

The first valid record for a unique SHA-1 becomes the in-memory lookup entry.

## Canonical naming and classification

When an exact or supported normalized DAT match exists, authoritative database metadata takes precedence over filename parsing. This includes canonical ROM naming and MiSTer-aware system information.

v1.2 also explicitly separates Genesis/Mega Drive and 32X classification: `.md` and `.gen` files are associated with Mega Drive/Genesis, while `.32x` files are associated with 32X before DAT metadata is applied.

Filename parsing remains useful for unmatched files and metadata not supplied by the database. Alternate releases are preserved rather than silently deleted, and collisions are reported instead of overwriting files.

## Reports

Results are published under:

```text
/media/fat/GameLibraryAudit/
```

The main review artifact is:

```text
MiSTer_Library_Audit.txt
```

It contains the audit summary, integrity metadata, database/cache health, per-system processing information, timing data, and copies of the major detailed reports.

Other generated files include:

| Report | Purpose |
| --- | --- |
| `game_library.txt` | Human-readable library inventory |
| `library_catalog.csv` | Structured catalog and classifications |
| `proposed_renames.csv` | Game filename proposals |
| `proposed_save_renames.csv` | Save filename proposals |
| `dat_matches.csv` | Successful hash/database matches |
| `unmatched_hashes.csv` | Hashed files not identified by the database |
| `hash_duplicates.csv` | Files sharing SHA-1 hashes |
| `location_audit.csv` | Current versus expected MiSTer locations |
| `hash_cache.tsv` / `hash_cache.meta` | Internal incremental hash cache |

Reports are generated in a staging area and then published as complete files so an interrupted audit is less likely to replace previous reports with partially generated output.

## Audit integrity

v1.2 embeds machine-readable audit metadata in the consolidated report, including:

- audit schema version;
- exporter version and build SHA-1;
- audit mode;
- database SHA-1 fingerprint;
- metadata-layer status;
- self-check status;
- integrity verdict; and
- Apply recommendation.

The completion screen surfaces an **Integrity verdict** and an **Apply recommendation**, including states such as `SAFE TO PREVIEW` or `DO NOT APPLY` as appropriate.

The exporter build itself is fingerprinted with SHA-1 so a report can be tied to the exact script that generated it.

## Reviewing the audit

For a normal cleanup pass:

```text
1. Run Export_Game_Library
2. Review MiSTer_Library_Audit.txt
3. Investigate unmatched ROMs, duplicates, location issues, and questionable proposals
4. Confirm the audit integrity verdict is acceptable
5. Run Update_Game_Library
6. Preview
7. Review proposed and skipped operations
8. Apply only when satisfied
9. Re-run the auditor after cleanup
```

`MiSTer_Library_Audit.txt` is designed to be the single file needed for a detailed ChatGPT review.

## Rename workflow

Run `Update_Game_Library` only after reviewing the audit.

### Preview

Preview builds a safety-checked plan without renaming files:

```text
/media/fat/GameLibraryAudit/apply_preview.tsv
/media/fat/GameLibraryAudit/apply_skipped.tsv
```

The updater rejects or skips operations when it detects conditions such as an out-of-root path, unsafe filename, missing source, existing destination, or duplicate destination. CUE renames are intentionally disabled because independently renaming members of a CUE/BIN disc set can break references.

### Apply

Apply rebuilds the preview, displays the candidate count, and requires the user to type `APPLY` exactly before any `mv` operation occurs.

Successful and unsuccessful operations are recorded in a timestamped manifest under:

```text
/media/fat/GameLibraryAudit/RenameHistory/
```

### Rollback

Rollback uses the most recent manifest and requires the user to type `ROLLBACK` exactly. Successful renames are processed in reverse order where they can be safely restored.

## Important current limitation

The auditor is **v1.2**, while `Update_Game_Library.sh` is still labeled **v1.1**. The exporter produces the v1.2 integrity verdict and Apply recommendation, but the current updater does **not** independently validate that v1.2 audit metadata before allowing Apply.

Until that handshake is implemented, treat the auditor's `DO NOT APPLY` recommendation as a hard manual stop. Always review the latest audit before using Apply.

## Safety invariants

- Auditing is read-only with respect to ROMs and saves.
- Rename proposals are review artifacts, not automatic actions.
- The updater is the only component in this repository intended to rename library files.
- Existing targets and duplicate proposed targets are not overwritten.
- Unsafe disc-set renames are skipped.
- Rename history is retained for rollback.
- Generated reports, caches, rename history, ROMs, and saves are runtime/user data and must not be managed as distributed content by MiSTer Update All.

## Project documentation

The [`wiki/`](wiki/) directory documents current implemented behavior in smaller, focused pages. [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md) records project-level development context and constraints.

GitHub is the source of truth for development. The intended development/distribution workflow is:

```text
ChatGPT / Codex → GitHub → VS Code → MiSTer
```

## Future work

Potential future work includes richer disc identification and coordinated disc-set handling, broader database coverage, improved save analysis, and evaluation of a possible TSV-to-SQLite database migration. SQLite is not part of the current architecture and should not be introduced without reviewing the design first.

Custom MiSTer Downloader / Update All integration is also planned around a generated `db.json`, downloader configuration, and GitHub Actions. Those distribution files are not part of the current runtime implementation unless and until they are added to the repository.

---

🎮 **Run the auditor first. Review the results. Preview changes. Modify the library only when the evidence says it is safe.**