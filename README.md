# MiSTerFPGAGameLibraryAudit

🎮 MiSTer FPGA Game Library Audit

A read-only-first toolkit for auditing, identifying, cleaning, and
safely renaming a MiSTer FPGA game library.

The solution is built around three files:

• Export_Game_Library.sh — audits the library and generates
reports and rename proposals.
• Update_Game_Library.sh — previews, applies, and rolls back
approved game/save filename changes.
• mister_hash_database.tsv — consolidated Nintendo No-Intro hash
lookup database used for SHA-1 identification.

> **Current release: v1.1**

Audit → Identify → Preview → Clean → Roll Back

Designed for a cleaner MiSTer library without blindly renaming or
deleting files.

🔎 What It Does

MiSTer Game Library Audit scans the games and saves on a MiSTer
installation, normalizes ROM metadata, identifies known files by SHA-1,
and produces reviewable cleanup reports before anything is changed.

The auditor is designed to distinguish a game’s title from metadata such
as region, revision, translation, hack, prototype, demo,
homebrew/unlicensed status, and other variants. It also filters known
BIOS, boot, firmware, test, and support files so they do not pollute
normal game-library statistics.

The updater is intentionally separate from the auditor. Auditing remains
read-only; filename changes happen only after an explicit preview and
confirmation.

📦 Installation

Copy these three files to:

```text
/media/fat/Scripts/
├── Export_Game_Library.sh
├── Update_Game_Library.sh
└── mister_hash_database.tsv
```

The scripts can then be launched from MiSTer’s Scripts menu.

The auditor creates its working/output directory automatically:

```text
/media/fat/GameLibraryAudit/
```

🚀 Recommended Workflow

1. Run Export_Game_Library.sh.
2. Let the audit finish and review the reports under
/media/fat/GameLibraryAudit/.
3. Check hash matches, unmatched files, proposed game renames, proposed
save renames, duplicate hashes, and skipped/support files.
4. Run Update_Game_Library.sh.
5. Choose Preview before applying changes.
6. Review the generated apply/skip reports.
7. Choose Apply only when the proposed changes look correct.
8. Use Rollback if a completed cleanup needs to be reversed.

📊 Audit Reports

The solution can generate reports including:

────────

File                               Purpose

────────

game_library.txt                 Human-readable inventory of
detected games

library_catalog.csv              Structured catalog with normalized
metadata and hashes

proposed_renames.csv             Review-only game filename
proposals

proposed_save_renames.csv        Save filename proposals associated
with games

dat_matches.csv                  Files positively identified by the
hash database

unmatched_hashes.csv             Files whose SHA-1 was not found in
the reference database

hash_duplicates.csv              Files sharing the same SHA-1

apply_preview.tsv                Changes the updater is prepared to
make

apply_skipped.tsv                Changes rejected by updater safety checks

Exact report availability can evolve with the scripts;
/media/fat/GameLibraryAudit/ is the authoritative output location.

🔐 Hash Identification

Version 1.1 includes SHA-1-based ROM identification.

mister_hash_database.tsv was built from uploaded Nintendo DAT metadata
and contains 28,570 unique SHA-1 hashes across the Nintendo sets
included in the database. The database allows identification to rely on
file contents instead of filenames whenever an exact hash match is
available.

Included reference sets cover the major Nintendo MiSTer targets used for
this project, including:

• Nintendo Entertainment System — headered and headerless
• Family Computer Disk System
• Super Nintendo Entertainment System
• Game Boy
• Game Boy Color
• Game Boy Advance
• Nintendo 64 — BigEndian and ByteSwapped
• Nintendo 64DD
• Selected specialized GBA sets supplied with the database

Hash matching is preferred over filename inference because filenames can
be incomplete, inconsistent, or wrong.

🌎 Regions and Alternate Versions

The auditor recognizes both long-form and common abbreviated ROM-set
region tags, including forms such as (USA), (U), (World),
(Europe), (E), (Japan), and (J).

When a primary copy eventually needs to be selected, the project’s
preferred region order is:

```text
USA → World → Europe → Japan → Other
```

Alternate versions are preserved rather than silently deleted. The audit
can distinguish categories such as retail/standard releases, revisions,
translations, hacks/modified ROMs, prototypes/betas/demos, and
homebrew/unlicensed material.

✨ Title Normalization

Filename cleanup removes ROM-set metadata while attempting to preserve
meaningful game titles, punctuation, subtitles, and numbering.

Normalization is deliberately conservative. A clean menu is useful;
losing the information needed to distinguish two different ROMs is not.

When multiple files would resolve to the same destination filename, the
updater must treat that as a collision rather than overwrite an existing
game.

🧩 BIOS and Support Files

BIOS, boot ROMs, firmware, machine ROMs, test software, and other
support files should not count as ordinary games.

The auditor includes filtering intended to keep these files out of
normal game totals and rename operations. Items that cannot be
classified safely should be reviewed rather than automatically changed.

🛠️ Game and Save Renaming

Update_Game_Library.sh provides three core operations:

Preview builds the proposed change plan without modifying the
library.

Apply performs safety-checked filename changes only after explicit
confirmation.

Rollback uses the recorded rename history to restore previously
changed paths.

The updater checks for conditions such as missing source files, existing
destinations, duplicate targets, unsafe paths, and unsupported disc-set
operations.

Rename history is stored under:

```text
/media/fat/GameLibraryAudit/RenameHistory/
```

💿 Disc-Based Games

Multi-file disc images require special care.

A .cue file can reference one or more .bin tracks. Renaming only the
CUE or only its tracks can break the game. For that reason, unsafe
CUE/BIN renaming is intentionally excluded from automatic cleanup until
coordinated disc-set handling is implemented.

CHD and other container formats can also require format-specific
identification because a DAT may describe normalized disc data rather
than the hash of the container itself.

🛡️ Safety Philosophy

The project follows a simple rule:

> 🛡️ **Identify first, preview second, modify last.**

The auditor does not rename, move, or delete games or saves. The updater
is a separate explicit action, requires confirmation before applying
changes, records what it changes, and provides rollback support.

Uncertain, ambiguous, colliding, or unsupported operations should be
skipped instead of guessed.

⚠️ Current Limitations

Hash identification only works when the exact file representation
matches an entry in the installed hash database. Header differences,
byte ordering, container formats, patched ROMs, hacks, translations, and
modified dumps may legitimately remain unmatched.

The bundled database currently focuses on the Nintendo DAT sets supplied
for this project. Other MiSTer platforms will need additional
authoritative DAT metadata before they can receive the same level of
hash-based identification.

USA-release completion auditing also requires a carefully defined
canonical release baseline; a raw ROM count should not be treated as a
count of unique official USA games.

🗺️ Roadmap

Future improvements can include:

• Additional No-Intro-backed platforms
• Redump-aware disc identification
• Header/byte-order normalization before hash lookup
• Coordinated CUE/BIN renaming
• System-aware save matching and orphan-save reporting
• Canonical primary-ROM selection
• USA retail completion reports and missing-title lists
• More detailed duplicate and cleanup recommendations
• External USB and _Arcade inventory support

🏷️ Version 1.1

Version 1.1 expands the original audit approach with improved region and
variant parsing, stronger BIOS/support filtering, collision-aware
cleanup, SHA-1 generation, Nintendo hash-database matching, dedicated
GameLibraryAudit output organization, and the companion
preview/apply/rollback updater.

The solution remains conservative by design: a questionable rename is
better skipped than guessed.