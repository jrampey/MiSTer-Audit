# Update All Installation

The repository publishes a MiSTer Downloader-compatible `db.json` so the Game Library Audit runtime files can be installed and updated through MiSTer Downloader / Update All.

## What gets installed

The custom database manages only these files:

- `/media/fat/Scripts/Export_Game_Library.sh`
- `/media/fat/Scripts/Update_Game_Library.sh`
- `/media/fat/Scripts/mister_hash_database.tsv`

Reports, caches, rename history, ROMs, saves, repository documentation, and wiki files are not managed by Update All.

## Add the custom database

MiSTer Downloader's primary configuration file is:

```text
/media/fat/downloader.ini
```

It is located at the root of the MiSTer SD card. A separate `/media/fat/downloader/` directory is not required.

Open `downloader.ini` and add this section:

```ini
[jrampey/MiSTerFPGAGameLibraryAudit]
db_url = https://raw.githubusercontent.com/jrampey/MiSTerFPGAGameLibraryAudit/main/db.json
```

Save the file, then run Update All normally.

Do not edit `Scripts/update_all.sh` to add the database.

## Automatic repository publishing

The repository contains `.github/workflows/build-downloader-db.yml`.

When any of these files changes on `main`:

- `Export_Game_Library.sh`
- `Update_Game_Library.sh`
- `mister_hash_database.tsv`

GitHub Actions rebuilds `db.json`, validates it with MiSTer Downloader, and commits the updated database back to the repository. The database includes the expected download URL, file size, and hash for each distributed runtime file.

This means the normal release path is:

1. Update a distributed runtime file in the repository.
2. Push the change to `main`.
3. GitHub Actions regenerates and validates `db.json`.
4. Run Update All on the MiSTer.
5. MiSTer Downloader updates any managed file whose published hash has changed.

## Safety boundary

Update All distributes the audit software and hash database only. It does not run the audit, apply rename proposals, move files, delete files, or modify ROMs and saves. Library mutation remains confined to the separate Preview / Apply / Rollback workflow in `Update_Game_Library.sh`.