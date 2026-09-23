# Migrating from Zotero Storage

The key fact: **when you switch to WebDAV, Zotero uploads the attachment files it has on the local disk.** It does not copy files from Zotero Storage to your server. Any file that exists only on zotero.org (for example because a device was set to download files "as needed") must be downloaded first, or it will be stranded on zotero.org when the subscription ends.

## 1. Pick one computer to do the migration

Use the computer that has the most complete local copy, ideally a desktop that has been set to download files "at sync time" all along.

## 2. Download every attachment

1. In Zotero on that computer: **Settings → Sync → File Syncing**, set **Download files** to **at sync time**.
2. Click the sync button (the green arrow) and wait until it finishes. With a large library this can take a while; keep Zotero open.
3. Spot-check: open a handful of old PDFs, especially ones you added on other devices. They should open without a download progress bar.

For a stronger check, compare the number of attachment folders on disk with the number Zotero expects. Your local files are in the `storage` folder of your Zotero data directory (Settings → Advanced → Files and Folders → Show Data Directory), one subfolder per attachment.

## 3. Back up the Zotero data directory

Quit Zotero and copy the whole data directory (the folder containing `zotero.sqlite` and `storage/`) somewhere safe. This is your fallback if anything goes wrong.

## 4. Switch to WebDAV

1. Install the server on the Mac Mini (`./install.sh`) and run `zwd-healthcheck --auth` there.
2. In Zotero on the migration computer, set File Syncing to **WebDAV** with your server details, click **Verify Server**, then sync.
3. Zotero now uploads every attachment. Watch the count grow on the Mac Mini:
   ```bash
   zwd-healthcheck      # shows "N attachments" in the data folder
   ```
4. When the sync finishes, the number of `.zip` files should roughly match the number of attachment folders in your local `storage/` directory. Linked files (as opposed to stored files) are never synced by Zotero, whatever the backend.

## 5. Switch your other devices

On each other computer and on the iOS app, change File Syncing to WebDAV with the same details and sync. They will download from the Mac Mini as needed.

## 6. Run the first backup

On the Mac Mini, run `zwd-backup` once by hand rather than waiting for 03:30, then check that `Backups/ZoteroDAV/current/zotero/` appears in OneDrive.

## 7. Let the subscription lapse

Once you are happy (give it a week or two of normal use), cancel the auto-renewal at zotero.org → Settings → Storage. You can also delete the old copies from Zotero's servers there if you prefer not to leave them behind; only do that after step 6.

## Rolling back

Switch File Syncing back to **Zotero** in Settings → Sync. Zotero will upload your local files to Zotero Storage again, subject to your quota. Your WebDAV folder is left untouched.
