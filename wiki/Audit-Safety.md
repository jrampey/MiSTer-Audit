# Audit Safety

## Catalog accounting integrity

The v1.4 auditor verifies that report generation accounts for the complete discovered library.

The report-generation loop reads its plan through a dedicated file descriptor so commands executed while processing one game cannot accidentally consume subsequent plan records.

Two integrity checks protect the resulting catalog:

- cataloged files must equal classified files;
- cataloged files plus intentionally skipped BIOS/support files must equal the number of files discovered.

If discovery accounting does not balance, the audit is marked `FAIL` and Apply is blocked with a `DO NOT APPLY` recommendation.

## Canonical duplicate accounting

Audit generation must never evaluate canonical filenames as arithmetic expressions. The exporter records every source row even when multiple source files resolve to the same canonical DAT filename. Integrity accounting still requires `cataloged + skipped = discovered`, and the regression suite includes the apostrophe-bearing duplicate canonical pattern that exposed Issue #6 on real MiSTer hardware.

## Final-target collision classification

Issue #7 separates a filename-parsing collision from a genuinely unsafe rename collision.

The first classification pass may group files under the same fallback proposal because filename normalization intentionally strips revision/region metadata. During report generation, exact or normalized SHA-1 DAT identity can replace that fallback with an authoritative canonical No-Intro filename.

After all rows are processed, each pre-DAT collision group is evaluated from temporary text records containing its authoritative-DAT flag and final target filename:

- when every row has authoritative DAT identity and every final target is unique, the rows are counted as **resolved canonical DAT variants**;
- when any row is unmatched or unsupported, or final targets are duplicated, the rows remain **blocking collisions**.

The exporter still reports blocking rows conservatively as `PASS WITH WARNINGS`, `DO NOT APPLY`, and `collision-review-required`. That warning remains useful review evidence, but it no longer forces unrelated safe rename rows to remain unapplied.

## Apply with blocking rows skipped

`MiSTer_Audit.sh` v1.4 can proceed when the audit's **only** warning is `collision-review-required`.

Before Preview or Apply, the updater reads `library_catalog.csv` and independently reconstructs the exporter's collision decision:

1. rebuild the pre-DAT fallback group from the original filename using the same region/type/title normalization rules;
2. mark exact and normalized SHA-1 DAT rows as authoritative;
3. count final proposed targets across the complete system catalog;
4. classify a row as blocking when its final target is duplicated or its pre-DAT group remains ambiguous.

Every blocking game row is excluded from `apply_preview.tsv` and written to `apply_skipped.tsv` with a collision reason. If that game has a paired save proposal, the save rename is skipped too. The original game/save files remain untouched.

The updater then applies only the remaining safe rows after the normal explicit `APPLY` confirmation. Immediately before mutation it revalidates the audit fingerprints and rebuilds the plan again.

This exception is intentionally narrow. `FAIL`, low-DAT or other non-collision warnings, exporter/database fingerprint changes, unsafe paths, existing targets, duplicate mutation targets, and unsupported CUE/BIN operations still block or skip exactly as before.

## Independent mutation-side safety

The updater continues to validate duplicate/existing targets during Preview and Apply even after collision filtering. Collision filtering therefore reduces unnecessary all-or-nothing blocking without weakening the final filesystem safety checks.

Collision evidence and counts are evaluated as text through temporary TSV/`awk` passes rather than filename-derived Bash associative-array arithmetic. This preserves the Issue #6 safety requirement for canonical names containing apostrophes or other punctuation.

Final-target duplicate detection spans the complete catalog, including differently named source files that resolve to one identical canonical DAT filename.
