# Full No-Intro ZIP validation — 2026-09-13

Validation source: user-supplied `No-Intro.zip` (252 DAT files).

## MiSTer-relevant mapped DAT coverage

31 current No-Intro DATs map to systems already represented by the auditor. After deterministic SHA-1 deduplication they contain **58,661 unique records**.

Per-system unique record counts:

- Amiga: 19,742
- ARCHIE: 294
- Atari2600: 876
- C64: 4,716
- GAMEBOY: 2,002
- GBA: 8,262
- GBC: 2,040
- Genesis: 2,861
- Intellivision: 208
- N64: 2,347
- NES: 9,795
- S32X: 213
- SMS: 709
- SNES: 4,129
- TGFX16: 467

The NES total includes the current Headered and Headerless NES DATs plus FDS/QD data. The source DATs contained 9,802 raw NES/FDS SHA-1 rows before 7 duplicate SHA-1 records were deterministically collapsed.

## Current-library NES result

The latest `library_catalog.csv` contains **303 NES rows with `dat_match=No match`**. Comparing every one of those recorded SHA-1 values against the complete 9,795-record NES/FDS SHA-1 set from this No-Intro ZIP produced:

**0 additional direct SHA-1 matches.**

This is strong evidence that simply expanding the production TSV with the full current No-Intro NES data will not resolve the remaining 303 NES misses. The remaining set is predominantly translations, hacks, homebrew/unlicensed/pirate/legacy variants or otherwise noncanonical content, with any remaining normalization edge cases requiring byte-level investigation rather than more DAT coverage.

## Builder compatibility finding

The current builder's TurboGrafx mapping strings do not match the exact current DAT names `NEC - PC Engine - TurboGrafx-16` and `NEC - PC Engine SuperGrafx`. Those aliases should be added before using this ZIP as a reproducible full-source rebuild input.

## Safety

No matching rules were weakened and no ROM-library mutation is implied by this validation. Project release remains v1.3.
