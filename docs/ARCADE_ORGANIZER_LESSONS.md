# Arcade Organizer lessons applied to Game Library Auditor

This document records five architectural rules adopted for v1.3 without changing the release version.

## 1. Metadata-first identity

SHA-1/DAT identity is authoritative whenever a canonical record exists. Filename parsing is fallback metadata only. Canonical DAT fields may override inferred title, region, release, system/folder, and naming metadata.

## 2. Derived indexes are disposable

`mister_hash_database.tsv` remains the canonical metadata source. Per-system DAT indexes under `GameLibraryAudit/dat_cache` are derived, versionable/disposable acceleration data. A database signature change invalidates them.

## 3. ROM and save trees are immutable inputs

The exporter is read-only for `/media/fat/games` and `/media/fat/saves`. Reports, caches, indexes, and proposed rename files are derived views. The exporter never renames, moves, or deletes ROMs or saves.

## 4. Library/system scope is explicit

Only systems detected in the user's game library are loaded into the active DAT index. Completion is calculated independently per active system against that system's complete eligible canonical denominator. An absent system contributes neither numerator nor denominator.

## 5. Configuration describes policy

`AUDIT_POLICY.conf` contains user policy, not implementation tuning. Completion region and release eligibility belong there. Worker count, cache formats, temp paths, hash algorithms, and index internals remain implementation details.

## State model

The long-term runtime model is:

`filesystem -> signature/state -> canonical identity -> derived reports`

Canonical metadata is preferred over filename inference. Persistent state is acceleration only and must be safe to discard and rebuild from the filesystem plus canonical database.
