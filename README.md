🎮 MiSTer FPGA Game Library Audit

A read-only-first toolkit for auditing, identifying, cleaning, and
safely renaming a MiSTer FPGA game library — with a streamlined
workflow for uploading one consolidated audit report to ChatGPT for
review.

> **Current release: v1.1**

Audit → Upload → Review → Preview → Clean → Roll Back

The project is designed around one rule:

> 🛡️ **Identify first, preview second, modify last.**

────────

📦 Required Files

Copy these three files to your MiSTer:

```text
/media/fat/Scripts/
├── Export_Game_Library.sh
├── Update_Game_Library.sh
└── mister_hash_database.tsv
```

What each file does

────────

File                                Purpose

────────

Export_Game_Library.sh            Read-only library auditor and
report generator

Update_Game_Library.sh            Preview, Apply, and Rollback tool
for approved filename changes

mister_hash_database.tsv          Nintendo SHA-1 reference database used for exact ROM identification

The original No-Intro DAT files are not required on the MiSTer. The
consolidated TSV database is the reference source used by the exporter.

────────

🔎 Export Workflow

Step 1 — Run the exporter

From the MiSTer menu, open Scripts and run:

```text
Export_Game_Library
```

The exporter scans the configured game and save directories without
modifying them.

During the audit it:

• inventories supported game files;
• calculates SHA-1 hashes;
• compares hashes against mister_hash_database.tsv;
• identifies canonical ROM information when an exact match exists;
• detects regions and alternate versions from filename metadata when
needed;
• detects duplicate hashes;
• filters BIOS, boot, firmware, test, and support files;
• checks for matching save files;
• detects rename collisions;
• generates game and save rename proposals;
• creates detailed CSV reports for the updater; and
• creates one consolidated report intended for ChatGPT.

> **The export process does not rename, move, or delete games or
> saves.**

────────

Step 2 — Review the completion summary

When the scan finishes, the MiSTer displays a summary of the audit.

The summary includes information such as:

• files cataloged;
• BIOS/support files skipped;
• SHA-1 hashes calculated;
• hash database matches;
• unmatched files;
• duplicate hashes;
• rename collisions;
• save matches; and
• reports generated.

The completion screen remains visible for 60 seconds and then closes
automatically.

You can press Enter to close it immediately.

────────

Step 3 — Find the results

The exporter stores its results under:

```text
/media/fat/GameLibraryAudit/
```

The most important file for sharing is:

```text
/media/fat/GameLibraryAudit/MiSTer_Library_Audit.txt
```

⭐ This is the file to upload to ChatGPT

You normally do not need to upload all of the individual CSV
reports.

MiSTer_Library_Audit.txt consolidates the information needed to review
the audit into a single file.

The individual reports remain on the MiSTer because
Update_Game_Library.sh uses them for cleanup operations.

────────

🤖 Uploading the Audit to ChatGPT

After the exporter finishes:

1. Open /media/fat/GameLibraryAudit/ through your preferred MiSTer
file-access method.
2. Locate MiSTer_Library_Audit.txt.
3. Copy or save that file to the device where you use ChatGPT.
4. Open the ChatGPT conversation for the MiSTer library project.
5. Tap the + attachment button.
6. Choose Files.
7. Select MiSTer_Library_Audit.txt.
8. Ask ChatGPT to review the audit.

For example:

```text
Review this v1.1 MiSTer library audit. Check the hash matches,
unmatched ROMs, duplicate hashes, bad title normalization,
region/version classification, BIOS/support files, collisions,
and game/save rename proposals. Tell me what should be fixed
before I run the updater.
```

ChatGPT can then use the consolidated report to evaluate the results
before any filename changes are applied.

Recommended rule

> 🚫 **Do not run Apply simply because the exporter completed
> successfully.**

Run the audit, upload the consolidated report, review questionable
results, and only then move on to the updater.

────────

📊 Local Audit Reports

The exporter retains detailed reports under
/media/fat/GameLibraryAudit/.

────────

Report                              Purpose

────────

MiSTer_Library_Audit.txt          Consolidated report intended for
ChatGPT review

game_library.txt                  Human-readable library inventory

library_catalog.csv               Structured catalog containing
classifications and hashes

proposed_renames.csv              Proposed game filename changes

proposed_save_renames.csv         Proposed save filename changes

dat_matches.csv                   Exact hash-database matches

unmatched_hashes.csv              Files not identified by the
installed hash database

hash_duplicates.csv               Files sharing an identical SHA-1
hash

RenameHistory/                    Rollback manifests created by the updater

The consolidated TXT file is for convenient review. The detailed CSV
files remain the machine-readable working data for the solution.

────────

🔐 Hash Identification

Version 1.1 uses SHA-1 fingerprints to identify ROMs independently
of their filenames.

The bundled Nintendo lookup database contains 28,570 unique SHA-1
hashes built from the Nintendo DAT sets prepared for this project.

When a file matches the database, the audit can use authoritative DAT
metadata instead of relying only on filename parsing.

Current Nintendo coverage includes major MiSTer targets such as:

• Nintendo Entertainment System — headered and headerless
• Family Computer Disk System
• Super Nintendo Entertainment System
• Game Boy
• Game Boy Color
• Game Boy Advance
• Nintendo 64 — BigEndian and ByteSwapped
• Nintendo 64DD
• selected specialized GBA sets included in the database

An unmatched hash does not automatically mean a ROM is bad. Headers,
byte ordering, patches, hacks, translations, modified dumps, or
unsupported systems can all produce legitimate unmatched files.

────────

🌎 Regions and Alternate Versions

The audit recognizes common long-form and abbreviated ROM metadata such
as:

```text
(USA)
(U)
(World)
(Europe)
(E)
(Japan)
(J)
```

When choosing a preferred regional copy, the project uses:

```text
USA → World → Europe → Japan → Other
```

Alternate releases are preserved rather than silently deleted.

The audit can distinguish categories including:

• Retail/Standard
• Revision
• Translation
• Hack/Modified
• Prototype/Beta/Demo
• Homebrew/Unlicensed

────────

✨ Title Normalization

The exporter attempts to remove ROM-set metadata while preserving
meaningful game titles, punctuation, subtitles, and numbering.

Normalization is intentionally conservative.

If multiple ROMs would resolve to the same destination filename, that
condition should be treated as a collision, not permission to
overwrite a file.

────────

🧩 BIOS and Support Files

BIOS files, boot ROMs, firmware, machine ROMs, test software, and other
support files should not be treated as normal games.

The exporter attempts to identify and exclude these from ordinary game
cleanup and completion statistics.

Anything that cannot be classified confidently should be reviewed rather
than automatically modified.

────────

🛠️ Cleanup Workflow

After the audit has been reviewed, run:

```text
Update_Game_Library
```

The updater provides three main operations.

👀 Preview

Builds the cleanup plan without changing the library.

Always run Preview first.

Review:

```text
/media/fat/GameLibraryAudit/apply_preview.tsv
/media/fat/GameLibraryAudit/apply_skipped.tsv
```

✅ Apply

Performs only the safety-checked filename changes in the approved plan.

Apply requires explicit confirmation.

The updater checks for problems such as:

• missing source files;
• existing destination files;
• duplicate destination names;
• unsafe paths;
• ambiguous operations; and
• unsupported disc-set changes.

↩️ Rollback

Restores filenames from the recorded rename manifest when a completed
cleanup needs to be reversed.

Rename history is stored under:

```text
/media/fat/GameLibraryAudit/RenameHistory/
```

────────

💾 Save Files

Game and save cleanup is coordinated so a renamed game does not
unnecessarily lose access to its corresponding save.

Save proposals are generated separately and remain reviewable before
Apply.

Ambiguous save matches should be skipped rather than guessed.

────────

💿 Disc-Based Games

Multi-file disc sets require additional safeguards.

A .cue file can reference one or more .bin tracks. Renaming only
part of that set can break the game.

For this reason, unsafe CUE/BIN rename operations are intentionally
excluded from automatic cleanup until coordinated disc-set handling is
implemented.

CHD and other container formats can also require format-specific
identification because reference DATs may describe normalized disc data
rather than the hash of the container file.

────────

🛡️ Safety

The intended workflow is:

```text
1. Export
2. Upload MiSTer_Library_Audit.txt to ChatGPT
3. Review the audit
4. Fix exporter/database issues if necessary
5. Run Update_Game_Library
6. Preview
7. Review skipped and proposed operations
8. Apply
9. Roll back if necessary
```

The exporter is read-only.

The updater is deliberately separate so simply auditing the library
cannot rename your games or saves.

> **A questionable rename is better skipped than guessed.**

────────

⚠️ Current Limitations

Hash identification requires the exact file representation to match an
entry in the installed database.

Legitimate files can remain unmatched because of:

• ROM headers;
• byte ordering;
• patches;
• translations;
• hacks;
• homebrew;
• modified dumps;
• container formats; or
• systems not yet represented in the database.

The current consolidated hash database focuses on the Nintendo DAT sets
prepared for this project.

Disc identification and coordinated multi-track renaming remain areas
for future development.

────────

🗺️ Roadmap

Potential future improvements include:

• additional No-Intro-backed systems;
• Redump-aware disc identification;
• header and byte-order normalization before hash lookup;
• coordinated CUE/BIN renaming;
• system-aware save matching;
• orphan-save reporting;
• canonical primary-ROM selection;
• USA retail completion statistics;
• missing-title reports;
• richer duplicate/cleanup recommendations;
• external USB library support; and
• _Arcade inventory support.

────────

🏷️ Version 1.1

Version 1.1 provides the current three-part solution:

```text
Exporter + Updater + Hash Database
```

It includes improved region/version parsing, stronger BIOS/support
filtering, collision-aware rename proposals, SHA-1 generation, Nintendo
hash matching, duplicate detection, dedicated audit output, a
consolidated ChatGPT upload report, and the Preview/Apply/Rollback
updater workflow.

🎮 Run the exporter first. Upload MiSTer_Library_Audit.txt to
ChatGPT. Review the results. Then clean the library.