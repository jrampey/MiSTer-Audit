# Synthetic Library Integration Test

This optional integration test runs the real `MiSTer_Audit.sh` against a deterministic, disposable library shaped like the production MiSTer library that exposed Issue #6.

## Profile

The generated fixture contains exactly:

- 6,575 discovered game-library files
- 6,469 catalog candidates
- 106 BIOS/support files that must be skipped
- multiple MiSTer systems and cartridge formats
- a smaller set of save files for save-pairing coverage
- real Full Verification SHA-1 calculation for representative supported formats
- a large Game Gear discovery/classification tail to keep CI runtime reasonable

No ROM data is stored in the repository. The fixture is generated from tiny deterministic synthetic files at test time.

## Regression guarantees

The test fails unless:

- `Games/discs cataloged == 6,469`
- `BIOS/support files skipped == 106`
- `6,469 + 106 == 6,575 files discovered`
- `library_catalog.csv` contains exactly 6,469 data rows
- sentinel records from early, middle, and tail portions of the generated plan survive report generation
- neither `catalog-count-mismatch` nor `discovery-accounting-mismatch` is emitted
- the integrity verdict is not `FAIL`
- game/save path-and-size manifests are unchanged by the read-only exporter

These assertions specifically protect the accounting/report-loop failure class discovered in Issue #6.

## Running it

Use GitHub Actions -> **Synthetic Library Test** -> **Run workflow**. The workflow is intentionally `workflow_dispatch` only, so it does not add time to normal pushes or releases.

The shell harness refuses to run unless `CI=true` and refuses to overlay an existing `/media/fat/games`, `/media/fat/saves`, or `/media/fat/GameLibraryAudit` tree.
