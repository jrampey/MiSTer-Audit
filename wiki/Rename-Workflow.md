# Rename Workflow

Renaming is intentionally separate from auditing. `Export_Game_Library.sh` only proposes changes; `Update_Game_Library.sh` is the mutation path.

## Preview

Preview rebuilds a plan from `proposed_renames.csv` and, when present, `proposed_save_renames.csv`. It writes:

- `/media/fat/GameLibraryAudit/apply_preview.tsv`
- `/media/fat/GameLibraryAudit/apply_skipped.tsv`

Candidates are skipped when the source is outside the expected games/saves root, the proposed filename is unsafe, the source is missing, the target already exists, or multiple proposals resolve to the same target. CUE game renames are disabled.

## Apply

Apply first runs Preview again. If safe candidates exist, the user must type `APPLY` exactly. The updater then renames files with `mv` and records each result in a timestamped manifest under:

`/media/fat/GameLibraryAudit/RenameHistory/`

The latest manifest is copied to `last_manifest.tsv` for rollback.

## Rollback

Rollback requires typing `ROLLBACK` exactly. Successful entries from the last manifest are processed in reverse order. A file is restored only when the renamed source exists and the original target path is free.

## Current implementation note

The updater is still labeled **v1.1**, while the auditor is **v1.2**. The current updater rebuilds its safety plan from the proposal CSV files, but it does **not currently validate the auditor's v1.2 schema version, build fingerprint, integrity verdict, or apply recommendation before Apply**. Treat the auditor's `SAFE TO PREVIEW` / `DO NOT APPLY` guidance as a manual gate until that handshake is implemented.

After Apply or Rollback, rerun the auditor to verify the library state.