# shellcheck shell=bash
# macOS parts of install.sh (launchd). Sourced by install.sh, not run directly.
# Expects lib/common.sh to be loaded and REPO_DIR to be set.

install_prerequisites() {
  if ! command -v rclone >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install it from https://brew.sh, or install rclone yourself, then re-run."
    info "Installing rclone with Homebrew"
    brew install rclone
  fi
}

# Default backup destination: the OneDrive app's folder, if there is one.
default_backup_dest() {
  local onedrive
  onedrive="$(find "$HOME/Library/CloudStorage" -maxdepth 1 -type d -name 'OneDrive*' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$onedrive" ]]; then
    info "Found OneDrive folder: $onedrive" >&2
    echo "$onedrive/Backups/ZoteroDAV"
  else
    warn "No OneDrive folder found in ~/Library/CloudStorage. Backups are disabled until you set BACKUP_DEST in $ZWD_CONFIG."
    echo ""
  fi
}

local_hostname() { scutil --get LocalHostName 2>/dev/null || hostname -s; }

# render <template> <dest>: fill in the __PLACEHOLDERS__ of a launchd plist.
render_plist() {
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

install_services() {
  local tmp daemon_plist agent_plist
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  info "Installing server LaunchDaemon (you may be asked for your password for sudo)"
  daemon_plist="/Library/LaunchDaemons/$ZWD_SERVER_LABEL.plist"
  render_plist "$REPO_DIR/launchd/$ZWD_SERVER_LABEL.plist" "$tmp/server.plist"
  sudo launchctl bootout "system/$ZWD_SERVER_LABEL" 2>/dev/null || true
  sudo install -m 644 -o root -g wheel "$tmp/server.plist" "$daemon_plist"
  bootstrap system "$daemon_plist" sudo
  sudo launchctl enable "system/$ZWD_SERVER_LABEL"

  agent_plist="$HOME/Library/LaunchAgents/$ZWD_BACKUP_LABEL.plist"
  launchctl bootout "gui/$(id -u)/$ZWD_BACKUP_LABEL" 2>/dev/null || true
  if [[ -n "$BACKUP_DEST" ]]; then
    info "Installing nightly backup LaunchAgent ($(printf '%02d:%02d' "${BACKUP_HOUR:-3}" "${BACKUP_MINUTE:-30}"))"
    mkdir -p "$HOME/Library/LaunchAgents"
    render_plist "$REPO_DIR/launchd/$ZWD_BACKUP_LABEL.plist" "$agent_plist"
    bootstrap "gui/$(id -u)" "$agent_plist"
  else
    rm -f "$agent_plist"
  fi
}

open_firewall() {
  local fw=/usr/libexec/ApplicationFirewall/socketfilterfw real_rclone
  if "$fw" --getglobalstate 2>/dev/null | grep -q enabled; then
    real_rclone="$(realpath "$RCLONE" 2>/dev/null || echo "$RCLONE")"
    info "macOS firewall is on; allowing incoming connections to $real_rclone"
    sudo "$fw" --add "$real_rclone" >/dev/null
    sudo "$fw" --unblockapp "$real_rclone" >/dev/null
  fi
}

post_install_notes() {
  cat <<EOF

To keep the server reachable, stop the Mac sleeping and restart after power cuts:
  sudo pmset -a sleep 0 disksleep 0 autorestart 1
EOF
  if [[ "$DATA_DIR" == /Volumes/* ]]; then
    cat <<EOF

Your attachments are on an external volume. If server.log shows
"Operation not permitted", give /bin/bash and rclone Full Disk Access in
System Settings > Privacy & Security (rclone is at $(realpath "$RCLONE" 2>/dev/null || echo "$RCLONE")).
EOF
  fi
}
