# Rename Workflow

Renaming is intentionally separate from auditing. `MiSTer_Audit.sh` only proposes changes; `MiSTer_Audit.sh` v1.4 is the mutation path.

## Audit handshake

Before Preview or Apply, the updater reads `[AUDIT_METADATA]` from `/media/fat/GameLibraryAudit/MiSTer_Library_Audit.txt` and validates that the proposals came from a compatible, trustworthy audit.

The updater requires the expected v1.4 audit contract, including:

- audit schema version `4`;
- exporter version `1.4`;
- `self_check=PASS`;
- `metadata_layer=MiSTer-aware`;
- a recognized integrity verdict and Apply recommendation; and
- the audit's exporter and hash-database SHA-1 fingerprints.

It compares the recorded exporter fingerprint with the currently installed `MiSTer_Audit.sh` and the recorded database fingerprint with the currently installed `mister_hash_database.tsv`. If either changed after the audit was generated, the old proposals are considered stale and a fresh audit is required.

Preview may still be useful when the audit reports warnings, but Apply is blocked unless the audit has `integrity_verdict=PASS` and an Apply recommendation that permits proceeding. `DO NOT APPLY` is enforced by the updater rather than being only a manual warning.

## Preview

Preview validates the audit handshake and rebuilds a plan from `proposed_renames.csv` and, when present, `proposed_save_renames.csv`. It writes:

- `/media/fat/GameLibraryAudit/apply_preview.tsv`
- `/media/fat/GameLibraryAudit/apply_skipped.tsv`

Candidates are skipped when the source is outside the expected games/saves root, the proposed filename is unsafe, the source is missing, the target already exists, or multiple proposals resolve to the same target. CUE game renames are disabled.

## Apply

Apply runs Preview again, requires a fully passing audit, and revalidates the audit handshake immediately before file mutation. If safe candidates exist, the user must type `APPLY` exactly.

Only after those checks does the updater rename files with `mv`. Each result is recorded in a timestamped manifest under:

`/media/fat/GameLibraryAudit/RenameHistory/`

The latest manifest is copied to `last_manifest.tsv` for rollback.

This second validation means a script or database change between Preview and Apply cannot silently authorize stale proposals.

## Rollback

Rollback remains intentionally independent of the current audit handshake so recovery stays available even if the auditor or database has changed since Apply.

Rollback requires typing `ROLLBACK` exactly. Successful entries from the last manifest are processed in reverse order. A file is restored only when the renamed source exists and the original target path is free.

## Current implementation

The auditor and updater are both **v1.4**. The previous v1.1/v1.2 mismatch has been resolved: Apply now consumes and enforces the auditor's v1.4 integrity metadata instead of relying on it only as a manual review gate.

After Apply or Rollback, rerun the auditor to verify the library state.