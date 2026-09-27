# Reports

All runtime output is written under `/media/fat/GameLibraryAudit`.

| File | Purpose |
|---|---|
| `MiSTer_Library_Audit.txt` | Consolidated human-readable audit; intended as the primary file to upload/review. |
| `game_library.txt` | Text library listing. |
| `library_catalog.csv` | Structured catalog of discovered game/disc entries and classification data. |
| `dat_matches.csv` | ROMs identified by the bundled hash database, including normalized `special_release_category` and `curated_destination`. |
| `unmatched_hashes.csv` | Hashed, eligible ROMs without a DAT match. |
| `hash_duplicates.csv` | Duplicate SHA-1 findings. |
| `location_audit.csv` | Current system/folder versus expected MiSTer-aware location findings. |
| `proposed_renames.csv` | Game filename and curated-destination proposals for review; does not mutate anything by itself. |
| `proposed_save_renames.csv` | Save filename/category proposals paired to game basenames; review only. |
| `needs_review.csv` | Unmatched or unknown content needing identity/DAT review. |
| `support_files.csv` | BIOS, firmware, diagnostic/test, utility, and miscellaneous support classifications. |
| `release_families.csv` | Owned release relationships grouped by canonical title, including release categories. |
| `disc_media.csv` | Conservative CUE/CHD/GDI/ISO inventory and release-category metadata. |
| `hash_cache.tsv` | Internal incremental SHA-1/DAT cache. |
| `hash_cache.meta` | Cache format and database-fingerprint metadata. |

## Consolidated report

`MiSTer_Library_Audit.txt` includes summary counts, audit metadata, database coverage, cache health, per-system processing, timing information, and embedded copies of the generated reports.

Important summary fields include the self-check result, integrity verdict, apply recommendation, exporter build SHA-1, database fingerprint, exact DAT match count, DAT-eligible ROM count, and cache hit rate.

## Publishing behavior

Reports are generated in a staging directory first. Complete replacements are then moved into the audit directory one file at a time, so an in-progress generation does not directly overwrite the previous report contents.
## ROM-type reporting

The normalized ROM types are `Retail/Standard`, `Homebrew`, `Unlicensed`, `Aftermarket`, `Prototype`, `Beta`, `Demo/Sample`, `Translation`, and `Hack/Modified`. `game_library.txt` prints the full taxonomy. Retail/Standard stays at the parent system folder; every non-retail type uses exactly `<system>/<ROM type>`—never a gameplay-genre folder and never a folder per ROM.
