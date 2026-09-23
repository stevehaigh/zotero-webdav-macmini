# Remote access with Tailscale

Tailscale puts your devices on a private network (a "tailnet") that works wherever they are, without opening ports on your router. Your server gets a stable name such as `mac-mini` or `zotero`, and your laptop and iPad can reach it from anywhere as if they were at home. It's free for personal use.

## Set up

1. **The server.** Install Tailscale and sign in. What matters is that Tailscale runs even when nobody is logged in.
   - **Raspberry Pi / Linux:** the standard install runs as a system service from boot.
     ```bash
     curl -fsSL https://tailscale.com/install.sh | sh
     sudo tailscale up
     ```
   - **Mac, option 1:** the open-source CLI version runs as a system daemon from boot:
     ```bash
     brew install tailscale
     sudo brew services start tailscale
     sudo tailscale up
     ```
   - **Mac, option 2:** the app versions (Mac App Store or standalone download from tailscale.com) are easier to manage, but they run in your login session. If you use one, turn on automatic login for your account (System Settings → Users & Groups) so Tailscale comes back after a power cut.
2. **Other devices.** Install Tailscale on your laptop, iPad and phone, and sign in with the same account.
3. **Disable key expiry for the server.** In the [admin console](https://login.tailscale.com/admin/machines), open the server's menu and choose **Disable key expiry**. Otherwise it drops off the tailnet every few months until you sign in again.
4. **Test.** From your laptop with Tailscale on:
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -X PROPFIND http://<server-name>:8080/zotero/
   ```
   `401` means the server answered and wants a password: good.

Use `http://<server-name>:8080` in Zotero. Traffic between Tailscale devices is encrypted by WireGuard, so plain HTTP is acceptable here, although Zotero will note that the connection isn't HTTPS.

## Real HTTPS with `tailscale serve`

Tailscale can issue a trusted certificate for the server's `*.ts.net` name and proxy HTTPS to the WebDAV server. Zotero then sees an ordinary HTTPS site.

1. In the admin console's **DNS** page, make sure **MagicDNS** is on and enable **HTTPS Certificates**.
2. On the server:
   ```bash
   zwd-tailscale-https
   ```
   It prints the URL, e.g. `https://mac-mini.tail1234.ts.net`.
3. In Zotero, choose scheme `https` and enter `mac-mini.tail1234.ts.net` (no port).
4. Optional but recommended: stop the server listening on your LAN, so Tailscale is the only way in. Edit `~/.config/zotero-webdav/config.env`:
   ```bash
   BIND_ADDR="127.0.0.1"
   ```
   then restart:
   ```bash
   sudo launchctl kickstart -k system/io.github.stevehaigh.zotero-webdav   # macOS
   sudo systemctl restart zotero-webdav                                   # Linux
   ```
   After this, the `http://…:8080` URLs stop working, so update every device to the HTTPS URL first.

To undo: `zwd-tailscale-https --off`, and set `BIND_ADDR=""` again.

`tailscale serve` only exposes the service to devices on your own tailnet. It is not the same as `tailscale funnel`, which would publish it to the internet; don't use funnel for this.
