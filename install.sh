#!/bin/bash
# Install (or update) the Zotero WebDAV server on this Mac.
# Safe to re-run: it keeps your existing config, password and data.
#
#   ./install.sh
#
# What it does:
#   1. installs rclone with Homebrew if needed
#   2. copies the scripts to ~/.local/share/zotero-webdav
#   3. creates ~/.config/zotero-webdav/config.env and a password (first run only)
#   4. installs a LaunchDaemon (server, starts at boot) and a LaunchAgent (nightly backup)
#   5. allows rclone through the macOS firewall if the firewall is on
#   6. runs a health check and prints the URL to put into Zotero
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

is_macos || die "This installer is for macOS."
[[ $EUID -ne 0 ]] || die "Run as your normal user, not with sudo. It will ask for sudo when needed."

# --- 1. rclone ---------------------------------------------------------------
if ! command -v rclone >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install it from https://brew.sh, or install rclone yourself, then re-run."
  info "Installing rclone with Homebrew"
  brew install rclone
fi
RCLONE="$(command -v rclone)"
info "Using $("$RCLONE" version | head -n 1) at $RCLONE"

# --- 2. scripts --------------------------------------------------------------
info "Installing scripts to $ZWD_PREFIX"
mkdir -p "$ZWD_PREFIX/bin" "$ZWD_PREFIX/lib" "$ZWD_LOG_DIR" "$ZWD_CONFIG_DIR"
chmod 700 "$ZWD_CONFIG_DIR"
cp "$REPO_DIR"/bin/zwd-* "$ZWD_PREFIX/bin/"
cp "$REPO_DIR/lib/common.sh" "$ZWD_PREFIX/lib/"
chmod 755 "$ZWD_PREFIX"/bin/zwd-*

# --- 3. config and password --------------------------------------------------
if [[ ! -f "$ZWD_CONFIG" ]]; then
  info "Creating $ZWD_CONFIG"
  onedrive="$(find "$HOME/Library/CloudStorage" -maxdepth 1 -type d -name 'OneDrive*' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$onedrive" ]]; then
    backup_dest="$onedrive/Backups/ZoteroDAV"
    info "Found OneDrive folder: $onedrive"
  else
    backup_dest=""
    warn "No OneDrive folder found in ~/Library/CloudStorage. Backups are disabled until you set BACKUP_DEST in $ZWD_CONFIG."
  fi
  sed -e "s|^RCLONE_BIN=.*|RCLONE_BIN=\"$RCLONE\"|" \
      -e "s|^BACKUP_DEST=.*|BACKUP_DEST=\"$backup_dest\"|" \
      "$REPO_DIR/config.example.env" > "$ZWD_CONFIG"
  chmod 600 "$ZWD_CONFIG"
else
  info "Keeping existing config $ZWD_CONFIG"
fi
load_config
mkdir -p "$DATA_DIR/zotero"

if [[ ! -s "$HTPASSWD_FILE" ]]; then
  info "Choose the username and password Zotero will use"
  "$ZWD_PREFIX/bin/zwd-set-password" --no-restart
fi

# --- 4. launchd --------------------------------------------------------------
render() {  # render <template> <dest>
  sed -e "s|__USER__|$(id -un)|g" \
      -e "s|__HOME__|$HOME|g" \
      -e "s|__PREFIX__|$ZWD_PREFIX|g" \
      -e "s|__LOG_DIR__|$ZWD_LOG_DIR|g" \
      -e "s|__BACKUP_HOUR__|${BACKUP_HOUR:-3}|g" \
      -e "s|__BACKUP_MINUTE__|${BACKUP_MINUTE:-30}|g" \
      "$1" > "$2"
  plutil -lint "$2" >/dev/null || die "Generated plist $2 is invalid"
}

# bootout is asynchronous; bootstrap can fail briefly with "Input/output error".
bootstrap() {  # bootstrap <domain> <plist> [sudo]
  local _
  for _ in 1 2 3 4 5; do
    ${3:+sudo} launchctl bootstrap "$1" "$2" 2>/dev/null && return 0
    sleep 1
  done
  ${3:+sudo} launchctl bootstrap "$1" "$2"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

info "Installing server LaunchDaemon (you may be asked for your password for sudo)"
daemon_plist="/Library/LaunchDaemons/$ZWD_SERVER_LABEL.plist"
render "$REPO_DIR/launchd/$ZWD_SERVER_LABEL.plist" "$tmp/server.plist"
sudo launchctl bootout "system/$ZWD_SERVER_LABEL" 2>/dev/null || true
sudo install -m 644 -o root -g wheel "$tmp/server.plist" "$daemon_plist"
bootstrap system "$daemon_plist" sudo
sudo launchctl enable "system/$ZWD_SERVER_LABEL"

agent_plist="$HOME/Library/LaunchAgents/$ZWD_BACKUP_LABEL.plist"
launchctl bootout "gui/$(id -u)/$ZWD_BACKUP_LABEL" 2>/dev/null || true
if [[ -n "$BACKUP_DEST" ]]; then
  info "Installing nightly backup LaunchAgent ($(printf '%02d:%02d' "${BACKUP_HOUR:-3}" "${BACKUP_MINUTE:-30}"))"
  mkdir -p "$HOME/Library/LaunchAgents"
  render "$REPO_DIR/launchd/$ZWD_BACKUP_LABEL.plist" "$agent_plist"
  bootstrap "gui/$(id -u)" "$agent_plist"
else
  rm -f "$agent_plist"
fi

# --- 5. firewall -------------------------------------------------------------
fw=/usr/libexec/ApplicationFirewall/socketfilterfw
if "$fw" --getglobalstate 2>/dev/null | grep -q enabled; then
  real_rclone="$(realpath "$RCLONE" 2>/dev/null || echo "$RCLONE")"
  info "macOS firewall is on; allowing incoming connections to $real_rclone"
  sudo "$fw" --add "$real_rclone" >/dev/null
  sudo "$fw" --unblockapp "$real_rclone" >/dev/null
fi

# --- 6. check and report -----------------------------------------------------
sleep 2
echo
"$ZWD_PREFIX/bin/zwd-healthcheck" || warn "Health check reported problems; see $ZWD_LOG_DIR/server.log"

lan="$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"
ts_name="$(tailscale_dns_name 2>/dev/null || true)"
echo
info "Done."
cat <<EOF

In Zotero: Settings > Sync > File Syncing > "My Library" using WebDAV
  Scheme: http    URL: ${lan}:${PORT}          (at home, on your LAN)
EOF
[[ -n "$ts_name" ]] && echo "  Scheme: http    URL: ${ts_name}:${PORT}   (anywhere, via Tailscale)"
cat <<EOF
  Username: $(cut -d: -f1 "$HTPASSWD_FILE")    Password: the one you set
Zotero adds /zotero/ to the URL itself; do not type it.

Useful commands (add $ZWD_PREFIX/bin to your PATH for convenience):
  zwd-healthcheck --auth     full read/write test
  zwd-backup                 run a backup now
  zwd-tailscale-https        serve over HTTPS on your tailnet
  zwd-set-password           change the password
Logs: $ZWD_LOG_DIR

To keep the server reachable, stop the Mac Mini sleeping:
  sudo pmset -a sleep 0 disksleep 0
EOF
