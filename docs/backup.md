# Backups and restoring

## What's backed up, and how

`zwd-backup` copies the WebDAV folder (`DATA_DIR`, by default `~/ZoteroDAV`) to `BACKUP_DEST` using `rclone sync`. The destination looks like this:

```
Backups/ZoteroDAV/
├── current/                      mirror of ~/ZoteroDAV as of the last run
│   └── zotero/KEY.zip, KEY.prop …
├── versions/
│   ├── 2026-10-01_033000/        files that run replaced or deleted, as they were before
│   └── …
└── last-backup.txt               time and result of the last run
```

Because changed and deleted files are moved into `versions/` rather than overwritten, a mistake that deletes attachments (in Zotero or on the Mac) can be undone for `BACKUP_KEEP_DAYS` days (default 90). Older version folders are pruned automatically.

Remember that your library data (items, notes, annotations stored in the database) is not in this folder; it lives on zotero.org and in each computer's `zotero.sqlite`. Back up your Zotero data directory with your normal computer backups (Time Machine, for example).

## Schedule

The backup runs daily at 03:30: on macOS from a LaunchAgent (if the Mac was asleep, it runs on wake), on Linux from a systemd timer (if the machine was off, it runs soon after it boots). To change the time, edit `BACKUP_HOUR` and `BACKUP_MINUTE` in `~/.config/zotero-webdav/config.env` and re-run `./install.sh`.

Run one now:

```bash
zwd-backup
```

On macOS the backup runs as a LaunchAgent (in your login session) because the OneDrive app only syncs while you are logged in. On a Mac server, turn on automatic login so it survives reboots. On Linux there is no such constraint: the timer runs whether or not anyone is logged in.

## Destination option A: the OneDrive folder (macOS default)

The installer looks for `~/Library/CloudStorage/OneDrive-*` and sets:

```bash
BACKUP_DEST="$HOME/Library/CloudStorage/OneDrive-Personal/Backups/ZoteroDAV"
```

The OneDrive app then uploads the files. With Files On-Demand, OneDrive may later free up local space by making backup files cloud-only; that's fine.

If OneDrive is signed out or not running, its folder disappears and `zwd-backup` fails deliberately rather than writing a "backup" onto the Mac's own disk. The health check reports a failed or stale backup.

**If `backup.log` shows `Operation not permitted`,** macOS is blocking the background job from the OneDrive folder. Either give Full Disk Access to `/bin/bash` and to rclone (System Settings → Privacy & Security → Full Disk Access; find rclone's real path with `realpath "$(which rclone)"`), or switch to option B.

## Destination option B: straight to OneDrive with rclone (Linux default)

rclone can talk to OneDrive directly, without the OneDrive app. This is the only option on Linux (there's no OneDrive app), and on a Mac it works without anyone logged in and avoids the macOS privacy prompts.

1. Create an rclone remote called `onedrive` (this opens a browser to sign in once):
   ```bash
   rclone config create onedrive onedrive
   ```
   Follow the prompts and choose your personal OneDrive when asked.

   On a machine without a browser (such as a Raspberry Pi), run `rclone authorize "onedrive"` on your Mac instead, and paste the token it prints into `rclone config` on the Pi. [raspberry-pi.md](raspberry-pi.md#4-set-up-the-onedrive-backup) walks through it.
2. Set the destination in `~/.config/zotero-webdav/config.env`:
   ```bash
   BACKUP_DEST="onedrive:Backups/ZoteroDAV"
   ```
3. Test with `zwd-backup`.

The same works for any rclone backend (Backblaze B2, an external disk, another server), for example `BACKUP_DEST="/Volumes/External/ZoteroDAV"`.

## Restoring

Stop the server first, so Zotero doesn't sync while you restore:

```bash
sudo launchctl bootout system/io.github.stevehaigh.zotero-webdav   # macOS
sudo systemctl stop zotero-webdav                                   # Linux
```

**Everything** (e.g. after replacing the Mac's disk): copy `current/` back.

```bash
source ~/.config/zotero-webdav/config.env   # sets BACKUP_DEST and DATA_DIR
rclone copy "$BACKUP_DEST/current" "$DATA_DIR" --progress
```

**One attachment, or files deleted by mistake:** find the attachment key (in Zotero, right-click the attachment → Show File; the folder name in `storage/` is the key), then look for `KEY.zip` and `KEY.prop` in `current/zotero/` or the most recent `versions/*/zotero/` folder before the mistake, and copy both back into the `zotero/` folder inside your `DATA_DIR`.

Then start the server again:

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/io.github.stevehaigh.zotero-webdav.plist   # macOS
sudo systemctl start zotero-webdav                                                               # Linux
```

Each `KEY.zip` is an ordinary zip of the attachment's folder, so you can also unzip one to get the PDF without Zotero at all.
