# Hash Database

The exporter uses the bundled `mister_hash_database.tsv` as its canonical lookup source. Legacy XML DAT-folder parsing is not used in v1.2.

## Required schema

The exporter expects this exact MiSTer-aware column order:

```text
sha1	canonical_title	canonical_rom_name	dat_source	size	crc32	md5	mister_system	mister_core	expected_folder	region	release_type	license_status
```

The first valid record for a unique SHA-1 wins when the in-memory index is built.

## Metadata used by the audit

A matching record can supply canonical title, canonical ROM filename, DAT source, MiSTer system, core, expected folder, region, release type, and license status. Canonical DAT identity takes precedence over filename-derived identity where available.

## Hash-eligible systems/formats

Current matching logic includes Nintendo cartridge systems plus Mega Drive/Genesis, 32X, Master System, Atari 2600, Intellivision, PC Engine/TurboGrafx-16, SuperGrafx-compatible extensions, Amiga, C64, and Archimedes formats represented by the eligibility rules.

Not every cataloged file is hash-eligible. Unsupported formats remain in the catalog and are counted as hash skips rather than disappearing from the audit.

## Database fingerprint

The exporter calculates a SHA-1 fingerprint of the bundled database. The fingerprint is written into audit metadata and cache metadata. DAT metadata cached from a previous run is trusted only while this fingerprint remains unchanged.