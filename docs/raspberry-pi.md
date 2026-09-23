# Zotero WebDAV on a Raspberry Pi

This guide sets up a Raspberry Pi as a dedicated Zotero WebDAV server. It was written for a **Raspberry Pi 3**, which is too small for Home Assistant these days but has plenty of power for serving PDFs. The same steps work unchanged on a Pi 4 or Pi 5 running Raspberry Pi OS, or on any Debian or Ubuntu machine with systemd.

The attachments live on a USB drive, not the SD card. The SD card only holds the operating system.

## Is a Pi 3 fast enough?

For this job, yes. What limits it is I/O, not CPU:

| | Pi 3 | Pi 4 |
|---|---|---|
| Ethernet | 100 Mbit/s (Pi 3B+: ~300 Mbit/s, but shares the USB 2 bus) | 1 Gbit/s |
| USB | USB 2, ~30–35 MB/s | USB 3 |
| RAM | 1 GB | 1–8 GB |

In practice a Pi 3 moves roughly 10 MB/s. The first upload of a large library takes a while (a few GB is a few minutes of transfer, plus per-file overhead), and after that Zotero syncs a handful of files at a time, which a Pi 3 handles without noticing. rclone uses well under 100 MB of RAM.

One Pi 3 specific tweak happens automatically: `zwd-set-password` uses a cheaper bcrypt cost (7 instead of 10) when it detects a Pi 3, because rclone checks the password hash on every request and the default cost makes each request noticeably slower on that CPU. Override with `BCRYPT_COST=10 zwd-set-password` if you prefer.

## What you need

- A Raspberry Pi 3 (or later) with its power supply. Use a proper 2.5 A supply for a Pi 3; phone chargers cause undervoltage problems, especially with a USB drive attached.
- A microSD card of 16 GB or more. A-rated cards from a known brand (A1 or A2) cope better with small writes.
- A USB drive for the attachments: a USB SSD, or a USB stick for a small library. A bus-powered 2.5" hard drive may draw more than a Pi 3's USB ports provide; use a powered hub or an SSD.
- An Ethernet cable. Wi-Fi works, but wired is more reliable for an always-on server.

## 1. Install Raspberry Pi OS Lite (64-bit)

1. On your Mac, install [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
2. Choose your Pi model, then **Raspberry Pi OS (other) → Raspberry Pi OS Lite (64-bit)**, and your SD card.
3. When Imager offers to customise settings, set:
   - hostname: `zotero` (the server will be `zotero.local` on your network)
   - a username and password
   - **Enable SSH** with password or, better, your public key
   - Wi-Fi only if you can't use Ethernet
4. Write the card, put it in the Pi, connect Ethernet and power, and wait a minute or two.
5. From your Mac: `ssh <username>@zotero.local`
6. Update everything:
   ```bash
   sudo apt update && sudo apt full-upgrade -y && sudo reboot
   ```

Give the Pi a fixed address: in your router, add a DHCP reservation for it. Tailscale will also give it a stable name, but a reservation keeps `zotero.local` predictable on the LAN.

## 2. Prepare the USB drive

**This erases the drive.** Plug it in and find its device name:

```bash
lsblk -o NAME,SIZE,MODEL,MOUNTPOINT
```

It is usually `sda`. Check the size and model match your drive, not the SD card (`mmcblk0`). Then partition, format and label it:

```bash
sudo apt install -y parted
sudo parted /dev/sda --script mklabel gpt mkpart zotero ext4 0% 100%
sudo mkfs.ext4 -L zotero /dev/sda1
```

Mount it permanently at `/mnt/zotero`, by UUID so it doesn't matter which port it's in:

```bash
sudo mkdir -p /mnt/zotero
UUID=$(sudo blkid -s UUID -o value /dev/sda1)
echo "UUID=$UUID /mnt/zotero ext4 defaults,noatime,nofail,x-systemd.device-timeout=30s 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount /mnt/zotero
sudo chown "$USER": /mnt/zotero
df -h /mnt/zotero
```

`nofail` lets the Pi boot even if the drive is missing, so you can still log in and fix things. The server itself won't start without the drive; see step 3.

## 3. Install the WebDAV server

```bash
sudo apt install -y git
git clone https://github.com/stevehaigh/zotero-webdav-macmini.git
cd zotero-webdav-macmini
./install.sh
```

When asked for the attachment folder, enter:

```
/mnt/zotero/ZoteroDAV
```

The installer notices that this is on the drive mounted at `/mnt/zotero` and sets `REQUIRE_MOUNTPOINT`. From then on the server (and the backup) refuse to run if the drive isn't mounted. Without that guard, a missing drive would leave the server serving an empty folder, and Zotero would conclude that every file had been deleted.

The installer then:

- installs `apache2-utils` (for the password hash) and the latest rclone from rclone.org
- asks for a WebDAV username and password
- installs and starts `zotero-webdav.service`, which starts at boot and, if the drive isn't mounted yet, keeps retrying every 15 seconds until it is
- enables `zotero-webdav-backup.timer` for a nightly backup at 03:30
- opens port 8080 if the `ufw` firewall is active
- runs a health check and prints the URL for Zotero

## 4. Set up the OneDrive backup

There's no OneDrive app for Linux, so the backup uses rclone's OneDrive support directly, with a remote named `onedrive`. The Pi has no browser, so you sign in on your Mac and paste a token into the Pi:

1. On the Mac:
   ```bash
   brew install rclone
   rclone authorize "onedrive"
   ```
   A browser opens; sign in to Microsoft. The terminal then prints a token (a block of JSON). Copy all of it.
2. On the Pi:
   ```bash
   rclone config
   ```
   - `n` for a new remote, name it `onedrive`
   - storage type: `onedrive`
   - leave `client_id` and `client_secret` blank; region `global`
   - "Edit advanced config?" `n`
   - "Use web browser to automatically authenticate?" `n`, then paste the token
   - choose **OneDrive Personal or Business**, then pick your drive
3. Test it:
   ```bash
   ~/.local/share/zotero-webdav/bin/zwd-backup
   ```
   and check `Backups/ZoteroDAV/` appears in OneDrive.

rclone refreshes the token by itself. If you ever change your Microsoft password, repeat this with `rclone config reconnect onedrive:`.

See [backup.md](backup.md) for what the backup keeps and how to restore.

## 5. Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Sign in with the link it prints, then disable key expiry for the Pi in the Tailscale admin console. Details, including HTTPS, are in [tailscale.md](tailscale.md).

## 6. Point Zotero at it

Use `zotero.local:8080` at home or `zotero:8080` over Tailscale, as described in [zotero-client.md](zotero-client.md). If you're moving from Zotero Storage, follow [migration.md](migration.md). If you're moving from the Mac server, see the next section.

## Moving from the Mac server to the Pi

Your laptops have full copies of every attachment (if they download "at sync time"), so the simplest route is to let Zotero re-upload:

1. Set up the Pi as above and check `zwd-healthcheck --auth` passes.
2. In Zotero on your main computer, change the WebDAV URL to the Pi, click **Verify Server**, and sync. Zotero uploads everything to the Pi.
3. Change the URL on your other devices.
4. Uninstall on the Mac: `./uninstall.sh`. Keep `~/ZoteroDAV` on the Mac until you're sure.

Faster alternative for a large library: copy the files across first, then switch Zotero, which then finds them already there.

```bash
# on the Mac, with the Mac server stopped
rsync -av ~/ZoteroDAV/zotero/ <username>@zotero.local:/mnt/zotero/ZoteroDAV/zotero/
```

## Looking after it

```bash
zwd-healthcheck --auth                          # full check
sudo systemctl status zotero-webdav             # service state
journalctl -u zotero-webdav -n 50               # server log
journalctl -u zotero-webdav-backup -n 50        # backup log
systemctl list-timers zotero-webdav-backup      # next backup
sudo apt update && sudo apt full-upgrade -y     # OS updates
sudo rclone selfupdate                          # rclone updates
```

To call the `zwd-*` commands by name, add them to your PATH:

```bash
echo 'export PATH="$HOME/.local/share/zotero-webdav/bin:$PATH"' >> ~/.bashrc
```

Consider turning on unattended security updates: `sudo apt install unattended-upgrades`.

SD cards are the Pi's weak spot. This setup writes little to the card (logs, and rclone's config), but keep a spare card around. If the card dies, the fix is: flash a new card, re-add the fstab line, clone the repo, run `install.sh` and `rclone config` again. Your attachments are safe on the USB drive and in OneDrive.
