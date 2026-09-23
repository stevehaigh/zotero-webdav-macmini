# Home Assistant on a Raspberry Pi 4

This guide moves Home Assistant off a general-purpose Mac onto a dedicated Raspberry Pi 4 running **Home Assistant OS** from a USB SSD. It isn't needed for the Zotero server; it's here because the same reasoning applies: services you depend on belong on a box you don't experiment with.

Why a Pi 4 rather than a VM on a Mac:

- The Pi 4 (and Pi 5) are officially supported by Home Assistant OS, which gives you the full setup: add-ons, one-click updates and full backups.
- USB radios (Zigbee, Z-Wave, Thread) plug straight in, with no passthrough to a VM.
- It draws a few watts.

A Pi 3 is no longer a good choice: it has half of Home Assistant's 2 GB minimum RAM, and recent releases have broken on it. Use a Pi 3 for [the Zotero server](raspberry-pi.md) instead.

## What you need

- **Raspberry Pi 4 with 2 GB RAM or more** (4 GB is comfortable).
- **The official Raspberry Pi 15 W USB-C power supply.** Undervoltage is the most common cause of odd Pi problems, and an SSD adds to the load.
- **An SSD in a USB 3 enclosure**, 64 GB or more (the enclosure matters more than the SSD). Some cheap USB–SATA adapters are unreliable with the Pi 4; enclosures with ASMedia controllers, or a Pi case with a built-in SSD slot such as the Argon ONE M.2, are known to work. Plug it into a **blue** USB 3 port.
- **Cooling**: a case with a heatsink or fan.
- **Ethernet** to your router.
- A spare microSD card for the one-off bootloader update.

Why not run from an SD card? Home Assistant writes to its database constantly and wears SD cards out, usually without warning.

## 1. Let the Pi 4 boot from USB

Pi 4 boards made since 2020 usually boot from USB already. To make sure, update the bootloader once:

1. In Raspberry Pi Imager, choose **Raspberry Pi 4**, then **Misc utility images → Bootloader (Pi 4 family) → USB Boot**, and write it to the spare SD card.
2. Put the card in the Pi and power it on with no other drives attached. After about 10 seconds the green LED blinks steadily (and a screen, if connected, turns green). The bootloader is updated.
3. Power off and remove the card. You won't need it again.

## 2. Write Home Assistant OS to the SSD

1. Connect the SSD to your Mac.
2. In Raspberry Pi Imager: **Raspberry Pi 4 → Other specific-purpose OS → Home assistants and home automation → Home Assistant → Home Assistant OS (RPi 4/400)**, and choose the SSD as the target.
3. Write it, then plug the SSD into a blue USB port on the Pi, connect Ethernet, and power on.
4. After a few minutes, open `http://homeassistant.local:8123`. The first start downloads the latest version and can take up to 20 minutes.

Give the Pi a DHCP reservation in your router so its address never changes.

If the Pi refuses to boot from the SSD whatever you try, there's a fallback: install HA OS on an SD card, then use **Settings → System → Storage → Move data disk** to put all of Home Assistant's data on the SSD. The SD card then only holds the OS, which is mostly read-only. It works, but it's two points of failure instead of one, so treat it as a last resort.

## 3. Move your existing Home Assistant across

1. On the **old** Home Assistant (the VM on the Mac): **Settings → System → Backups → Backup now**, as a full backup. Download it to your Mac. Note the backup's encryption key (Settings → System → Backups → the menu → Encryption key) if backups are encrypted.
2. **Shut down the old Home Assistant VM.** Two instances controlling the same devices will fight.
3. If you have a USB radio stick, move it to the Pi. Use a short USB **extension cable** and plug it into a USB 2 (black) port: USB 3 ports and SSDs radiate interference in the 2.4 GHz band that Zigbee uses.
4. On the new Pi's onboarding screen, choose **Upload backup** (or "Restore from backup"), pick the file, and enter the key if asked. Home Assistant restores your configuration, add-ons and history, and restarts.
5. Check your integrations under **Settings → Devices & services**. Anything that talked to the old machine's IP address may need updating. Cloud-based integrations generally just carry on.

## 4. Remote access with Tailscale

Install the Tailscale add-on: **Settings → Add-ons → Add-on store**, search for **Tailscale**, install, start, and open its web UI to sign in. The Pi then appears on your tailnet as `homeassistant`, reachable at `http://homeassistant:8123` from anywhere. In the Tailscale admin console, disable key expiry for it.

The Home Assistant apps on your phone can use the Tailscale address as the external URL.

## 5. Backups

Home Assistant can back itself up on a schedule and copy the backups off the Pi:

1. **Settings → System → Backups → Configure automatic backups**: daily, keep 7 or so.
2. Add an off-device location. Home Assistant's backup integrations include cloud storage such as Microsoft OneDrive and Google Drive (**Settings → Devices & services → Add integration**), and network storage (**Settings → System → Storage → Add network storage**). Once added, it appears as a location in the backup settings.
3. Store the backup encryption key somewhere safe, such as your password manager. Without it the backups can't be restored.

## Housekeeping

- Updates appear under **Settings**. Apply the OS and Core updates every month or so, and leave the "create backup" option ticked when you update.
- Keep an eye on temperature: the **System Monitor** integration adds a CPU temperature sensor. It should stay below about 70 °C.
- If the Pi becomes unreachable, check the power supply first.
