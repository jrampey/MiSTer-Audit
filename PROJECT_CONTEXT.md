# MiSTer FPGA Game Library Audit — Project Context

We are continuing my MiSTer FPGA project from another ChatGPT conversation. The GitHub repository jrampey/MiSTerFPGAGameLibraryAudit is now the source of truth. Before making changes, inspect the current repository files and understand the existing implementation.

The current Game Library Audit release is v1.2. Do not increment the release version unless I explicitly tell you to.

The project audits my complete /media/fat/games library. It uses hash/DAT identification, MiSTer-aware system metadata, canonical No-Intro naming, region/release classification, save pairing, duplicate detection, location auditing, safe rename proposals, Full Verification/Fast Audit modes, caching, and consolidated MiSTer_Library_Audit.txt reports.

The hash database currently contains roughly 42,259 unique SHA-1 records and has been expanded beyond Nintendo with No-Intro data for Genesis/Mega Drive, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx, Amiga, C64, and Archimedes. We have discussed eventually replacing the TSV database with SQLite, but do not make that migration without reviewing the architecture first.

Important v1.2 work includes DAT-driven canonical naming, Genesis-vs-32X classification, NES/SNES normalized-hash fallback, exporter build fingerprints, mandatory MiSTer-aware database-schema validation, and an audit integrity verdict with SAFE TO PREVIEW / DO NOT APPLY recommendations.

Safety is important: auditing should be read-only. Renaming is handled separately through Preview/Apply/Rollback. Never automatically rename, move, or delete ROMs or saves. Generated reports, caches, rename history, ROMs, and saves must not be managed by Update All.

We also created a separate MiSTer Health Check project. It should remain logically separate from the Game Library Audit and be read-only by default.

We are setting up GitHub as the central development/distribution source so the workflow becomes: ChatGPT/Codex → GitHub → VS Code → MiSTer Update All.

We have also been working on custom MiSTer Downloader/Update All integration using a db.json, a drop-in downloader INI, and GitHub Actions to regenerate the database when distributed files change.

Important: because the project went through several intermediate builds, do not assume an old chat artifact is newer than GitHub. Inspect the actual repository before modifying anything. GitHub is now authoritative.

First, inspect the entire repository and give me a short assessment of its current state, including any inconsistencies or missing pieces. Do not change anything until I approve the assessment.
