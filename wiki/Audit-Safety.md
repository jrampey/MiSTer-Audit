# Audit Safety
## Catalog accounting integrity

The v1.3 auditor verifies that report generation accounts for the complete discovered library.

The report-generation loop reads its plan through a dedicated file descriptor so commands executed while processing one game cannot accidentally consume subsequent plan records.

Two integrity checks protect the resulting catalog:

- cataloged files must equal classified files;
- cataloged files plus intentionally skipped BIOS/support files must equal the number of files discovered.

If discovery accounting does not balance, the audit is marked `FAIL` and Apply is blocked with a `DO NOT APPLY` recommendation.
