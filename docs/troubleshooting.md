# Troubleshooting

Start with the health check on the server, then the logs:

```bash
zwd-healthcheck --auth

# macOS
tail -50 ~/Library/Logs/zotero-webdav/server.log
tail -50 ~/Library/Logs/zotero-webdav/backup.log

# Linux / Raspberry Pi
journalctl -u zotero-webdav -n 50
journalctl -u zotero-webdav-backup -n 50
```

For more detail, set `LOG_LEVEL="INFO"` in `~/.config/zotero-webdav/config.env` and restart the server. It then logs every request. Set it back afterwards, because the log grows quickly.

## Zotero: "Verify Server" fails

| Zotero says | Likely cause | Fix |
|---|---|---|
| Could not connect / server unreachable | Wrong host or port, the server is asleep or off, Tailscale is off on this device, or a firewall | Test from the same device with `curl -X PROPFIND http://HOST:8080/zotero/` (expect 401). On a Mac, check `pmset -g` shows `sleep 0`. Re-run `install.sh` to re-apply the firewall exception. |
| Authentication failed / 401 | Wrong username or password | Run `zwd-set-password` on the server and enter the new one in Zotero. |
| "The WebDAV server returned ... for a request to /zotero/" or not found | You typed `/zotero/` into the URL, so Zotero looks for `/zotero/zotero/` | Remove it; enter only host and port. |
| Certificate error with `https` | HTTPS certificates are not enabled in Tailscale, or you used an `http` URL with the `https` scheme | See [tailscale.md](tailscale.md#real-https-with-tailscale-serve). |

## The server isn't running (macOS)

```bash
sudo launchctl print system/io.github.stevehaigh.zotero-webdav | grep -E 'state|last exit'
```

- `last exit code = 1` over and over: read `server.log`. Common causes are a missing `htpasswd` file (run `zwd-set-password`), rclone moved (for example Homebrew relocated it; fix `RCLONE_BIN` in the config), or the port is already in use (`lsof -iTCP:8080 -sTCP:LISTEN`).
- Run it in the foreground to see errors directly:
  ```bash
  sudo launchctl bootout system/io.github.stevehaigh.zotero-webdav
  zwd-serve                 # Ctrl-C to stop
  sudo launchctl bootstrap system /Library/LaunchDaemons/io.github.stevehaigh.zotero-webdav.plist
  ```

## The server isn't running (Linux / Raspberry Pi)

```bash
sudo systemctl status zotero-webdav
journalctl -u zotero-webdav -n 50
```

- **"Data drive /mnt/zotero is not mounted"**: the USB drive is unplugged, or didn't mount at boot. Check with `lsblk` and `findmnt /mnt/zotero`; try `sudo mount /mnt/zotero`, and check the UUID in `/etc/fstab` matches `sudo blkid`. systemd retries every 15 seconds, so once the drive is mounted the server starts by itself.
- **Permission denied under the data folder**: the drive must be owned by the user the service runs as. `sudo chown -R "$USER": /mnt/zotero`.
- **Pi-specific instability** (random disconnects, the drive vanishing, corrupted files): almost always power. `vcgencmd get_throttled` should print `throttled=0x0`; anything else means undervoltage. Use the official power supply, or a powered USB hub for the drive.
- Run it in the foreground to see errors directly:
  ```bash
  sudo systemctl stop zotero-webdav
  zwd-serve                 # Ctrl-C to stop
  sudo systemctl start zotero-webdav
  ```

## After an rclone upgrade the Mac firewall blocks connections

Homebrew installs each rclone version at a new path, and the macOS firewall allows specific binaries. Re-run `./install.sh`, which re-adds the current binary.

## Backups

- **"Backup location … does not exist. Is OneDrive running and signed in?"** The OneDrive folder is missing, usually because OneDrive is signed out or nobody is logged in on the Mac. Open OneDrive, then run `zwd-backup`.
- **`Operation not permitted`**: macOS privacy controls. See [backup.md](backup.md#destination-option-a-the-onedrive-folder-macos-default).
- **Health check says the last backup is over 2 days old**: the LaunchAgent isn't running. It only runs while you are logged in; check with `launchctl print gui/$(id -u)/io.github.stevehaigh.zotero-webdav-backup`, and re-run `install.sh` if it's missing. On Linux, check the timer with `systemctl list-timers zotero-webdav-backup` and the last run with `journalctl -u zotero-webdav-backup -n 50`.
- **"rclone remote 'onedrive:' is not configured"**: set up the OneDrive remote as in [raspberry-pi.md](raspberry-pi.md#4-set-up-the-onedrive-backup).
- **OneDrive errors such as `invalid_grant` or `token expired`**: the sign-in has lapsed, typically after a Microsoft password change. Run `rclone config reconnect onedrive:` (on a Pi, with a token from `rclone authorize "onedrive"` on your Mac).

## Zotero says a file is missing on the server

This usually means the file was never uploaded, for example because the device that added it hasn't synced since. Sync that device. If the attachment exists only in a backup, restore it as described in [backup.md](backup.md#restoring).

## Resetting Zotero's view of the server

If Zotero and the server disagree after a restore, use **Settings → Sync → Reset → Reset File Sync History** in Zotero. On the next sync Zotero compares every file with the server again. It does not delete anything.
