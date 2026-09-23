#!/bin/bash
# Install (or update) the Zotero WebDAV server on this machine.
# Works on macOS (launchd) and on Raspberry Pi OS / Debian / Ubuntu (systemd).
# Safe to re-run: it keeps your existing config, password and data.
#
#   ./install.sh
#
# What it does:
#   1. installs rclone (Homebrew on macOS, rclone.org's installer on Linux)
#   2. copies the scripts to ~/.local/share/zotero-webdav
#   3. first run only: asks where to keep attachments, writes
#      ~/.config/zotero-webdav/config.env and sets a password
#   4. installs the services: server at boot + nightly backup
#      (macOS: LaunchDaemon + LaunchAgent; Linux: systemd service + timer)
#   5. opens the firewall for the server if a firewall is active
#   6. runs a health check and prints the URL to put into Zotero
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

[[ $EUID -ne 0 ]] || die "Run as your normal user, not with sudo. It will ask for sudo when needed."
if is_macos; then
  # shellcheck source=lib/install-macos.sh
  source "$REPO_DIR/lib/install-macos.sh"
elif is_linux; then
  # shellcheck source=lib/install-linux.sh
  source "$REPO_DIR/lib/install-linux.sh"
else
  die "Unsupported system $(uname -s). This installer supports macOS and Linux."
fi

# --- 1. prerequisites and rclone (OS-specific) --------------------------------
install_prerequisites
RCLONE="$(command -v rclone)" || die "rclone installation failed."
info "Using $("$RCLONE" version | head -n 1) at $RCLONE"

# --- 2. scripts --------------------------------------------------------------
info "Installing scripts to $ZWD_PREFIX"
mkdir -p "$ZWD_PREFIX/bin" "$ZWD_PREFIX/lib" "$ZWD_CONFIG_DIR"
[[ -n "$ZWD_LOG_DIR" ]] && mkdir -p "$ZWD_LOG_DIR"
chmod 700 "$ZWD_CONFIG_DIR"
cp "$REPO_DIR"/bin/zwd-* "$ZWD_PREFIX/bin/"
cp "$REPO_DIR/lib/common.sh" "$ZWD_PREFIX/lib/"
chmod 755 "$ZWD_PREFIX"/bin/zwd-*

# --- 3. config and password (first run) --------------------------------------
if [[ ! -f "$ZWD_CONFIG" ]]; then
  info "Creating $ZWD_CONFIG"

  default_data="$HOME/ZoteroDAV"
  echo "Where should the attachments be stored? Use a folder on an external drive"
  echo "if you have one (e.g. /mnt/zotero/ZoteroDAV), otherwise accept the default."
  read -r -p "Attachment folder [$default_data]: " data_dir
  data_dir="${data_dir:-$default_data}"
  data_dir="${data_dir/#\~/$HOME}"
  [[ "$data_dir" == /* ]] || die "Please give an absolute path."

  # If the folder lives on a separate drive, remember that drive's mount point so
  # the server refuses to start when it isn't mounted.
  mount_point="$(mount_point_of "$data_dir")"
  case "$mount_point" in
    /|/System/Volumes/Data|/home) mount_point="" ;;
    *) info "$data_dir is on the drive mounted at $mount_point; the server won't start unless it is mounted." ;;
  esac

  backup_dest="$(default_backup_dest)"
  sed -e "s|^DATA_DIR=.*|DATA_DIR=\"$data_dir\"|" \
      -e "s|^REQUIRE_MOUNTPOINT=.*|REQUIRE_MOUNTPOINT=\"$mount_point\"|" \
      -e "s|^RCLONE_BIN=.*|RCLONE_BIN=\"$RCLONE\"|" \
      -e "s|^BACKUP_DEST=.*|BACKUP_DEST=\"$backup_dest\"|" \
      "$REPO_DIR/config.example.env" > "$ZWD_CONFIG"
  chmod 600 "$ZWD_CONFIG"
else
  info "Keeping existing config $ZWD_CONFIG"
fi
load_config
require_data_mount
mkdir -p "$DATA_DIR/zotero"

if [[ ! -s "$HTPASSWD_FILE" ]]; then
  info "Choose the username and password Zotero will use"
  "$ZWD_PREFIX/bin/zwd-set-password" --no-restart
fi

# --- 4 & 5. services and firewall (OS-specific) ------------------------------
install_services
open_firewall

# --- 6. check and report -----------------------------------------------------
sleep 3
echo
"$ZWD_PREFIX/bin/zwd-healthcheck" || warn "Health check reported problems; see $(log_hint server)"

lan="$(local_hostname).local"
ts_name="$(tailscale_dns_name 2>/dev/null || true)"
echo
info "Done."
cat <<EOF

In Zotero: Settings > Sync > File Syncing > "My Library" using WebDAV
  Scheme: http    URL: ${lan}:${PORT}          (at home, on your LAN)
EOF
if [[ -n "$ts_name" ]]; then
  echo "  Scheme: http    URL: ${ts_name}:${PORT}   (anywhere, via Tailscale)"
else
  echo "  (Install Tailscale to sync from anywhere: see docs/tailscale.md)"
fi
cat <<EOF
  Username: $(cut -d: -f1 "$HTPASSWD_FILE")    Password: the one you set
Zotero adds /zotero/ to the URL itself; do not type it.

Useful commands (add $ZWD_PREFIX/bin to your PATH for convenience):
  zwd-healthcheck --auth     full read/write test
  zwd-backup                 run a backup now
  zwd-tailscale-https        serve over HTTPS on your tailnet
  zwd-set-password           change the password
Logs: $(log_hint server)
EOF
post_install_notes
