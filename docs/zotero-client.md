# Configuring Zotero

Do this on every device that uses your library. The settings are per device, not per account.

## Zotero desktop (7 or later)

1. Open **Settings → Sync**. Make sure you are signed in to your Zotero account under **Data Syncing**; library data still syncs through zotero.org.
2. Under **File Syncing**, tick **Sync attachment files in My Library using** and choose **WebDAV**.
3. Fill in:
   - **URL**: pick the scheme from the drop-down (`http` or `https`), then type the host and port, e.g. `mac-mini.local:8080`. Don't add `/zotero/`; Zotero adds it and shows it after the box.
   - **Username** and **Password**: the ones you chose in `install.sh` or `zwd-set-password`.
4. Click **Verify Server**. You should see "File sync is successfully set up".
5. Choose **Download files**: *at sync time* keeps a full copy on the device, *as needed* fetches each file when you open it. On a laptop with space, *at sync time* is the safer choice: every full copy is another backup.

### Which URL?

| Situation | Scheme | URL |
|---|---|---|
| Device on the same home network | `http` | `<LocalHostName>.local:8080` (the installer prints it) |
| Device anywhere, with Tailscale running | `http` | `<tailscale-machine-name>:8080` |
| Device anywhere, after `zwd-tailscale-https` | `https` | `<machine>.<tailnet>.ts.net` (no port) |

If you use a laptop both at home and away, use one of the Tailscale URLs everywhere. Tailscale works on the home network too, so you never have to change settings.

### Groups

Group libraries can't use WebDAV. Their files stay on zotero.org and count against the group owner's storage.

## Zotero for iOS / iPadOS

1. **Settings → Account**, sign in to your Zotero account if you haven't already.
2. **File Syncing → WebDAV** and enter the same scheme, URL, username and password.
3. Tap **Verify Server**.

To sync away from home, install the Tailscale app on the iPad or iPhone and keep it connected. Use the Tailscale URL.

## Zotero for Android

The official Android app is newer; check whether its settings offer WebDAV file syncing. If they do, the same settings apply.
