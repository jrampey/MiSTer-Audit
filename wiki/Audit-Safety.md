# Audit Safety

## Catalog accounting integrity

The v1.3 auditor verifies that report generation accounts for the complete discovered library.

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

- when every row has authoritative DAT identity and every final target is unique, the rows are counted as **resolved canonical DAT variants** and do not trigger `collision-review-required`;
- when any row is unmatched or unsupported, or final targets are duplicated, the rows remain **blocking collisions** and force `PASS WITH WARNINGS` plus `DO NOT APPLY`.

The audit summary reports pre-DAT collision rows, safely resolved canonical DAT variant rows, and blocking collision rows separately. The updater still validates duplicate/existing targets during Preview and Apply, so final-target classification does not remove the mutation-side safety checks.

Collision evidence is evaluated as text through a temporary TSV/`awk` pass rather than filename-derived Bash associative-array arithmetic. This preserves the Issue #6 safety requirement for canonical names containing apostrophes or other punctuation.
