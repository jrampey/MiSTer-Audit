# Safety and Invariants

These boundaries describe the current project design and should remain true unless deliberately redesigned.

## Auditor

`MiSTer_Audit.sh` is read-only with respect to ROMs and saves. It may scan, hash, classify, cache metadata, and write audit/report files, but it does not rename, move, or delete games or saves.

## Updater

`MiSTer_Audit.sh` is the only current script that mutates game/save filenames. Mutation requires an explicit Apply action and exact confirmation text. Rollback is also explicit and manifest-driven.

## Rename safeguards

The updater currently enforces root-path checks, unsafe-filename checks, source existence, target nonexistence, duplicate-target prevention, and a CUE rename block. Apply rechecks source/target existence before each move.

## Generated state

Reports, caches, preview files, skip files, and rename history live under `/media/fat/GameLibraryAudit`. They are runtime state, not library content.

## Distribution boundary

ROMs, saves, generated audit reports, caches, and rename history are not distribution artifacts and must not be managed by MiSTer Update All.

## Separate project boundary

The MiSTer Health Check project is separate from this Game Library Audit and should not be folded into this repository's audit/update behavior.

## Version boundary

The current Game Library Audit release is **v1.2**. Do not increment the release version merely for documentation or maintenance changes unless explicitly directed.