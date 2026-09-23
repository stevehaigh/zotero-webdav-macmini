#!/bin/bash
# Remove the Zotero WebDAV services and scripts (macOS or Linux).
# Your attachment data (DATA_DIR) and backups are never touched.
#
#   ./uninstall.sh                remove services and scripts, keep config + password
#   ./uninstall.sh --purge-config also delete ~/.config/zotero-webdav
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

if is_macos; then
  info "Stopping and removing the server LaunchDaemon (needs sudo)"
  sudo launchctl bootout "system/$ZWD_SERVER_LABEL" 2>/dev/null || true
  sudo rm -f "/Library/LaunchDaemons/$ZWD_SERVER_LABEL.plist"

  info "Removing the backup LaunchAgent"
  launchctl bootout "gui/$(id -u)/$ZWD_BACKUP_LABEL" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$ZWD_BACKUP_LABEL.plist"
elif is_linux; then
  info "Stopping and removing the systemd units (needs sudo)"
  sudo systemctl disable --now "$ZWD_BACKUP_TIMER" "$ZWD_SERVER_UNIT" 2>/dev/null || true
  sudo rm -f "/etc/systemd/system/$ZWD_SERVER_UNIT" \
             "/etc/systemd/system/$ZWD_BACKUP_UNIT" \
             "/etc/systemd/system/$ZWD_BACKUP_TIMER"
  sudo systemctl daemon-reload
else
  die "Unsupported system $(uname -s)."
fi

info "Removing scripts from $ZWD_PREFIX"
rm -rf "$ZWD_PREFIX"

data_dir="$HOME/ZoteroDAV"
if [[ -f "$ZWD_CONFIG" ]]; then
  # shellcheck source=/dev/null
  data_dir="$(source "$ZWD_CONFIG"; echo "${DATA_DIR:-$HOME/ZoteroDAV}")"
fi

if [[ "${1:-}" == "--purge-config" ]]; then
  info "Removing config and password from $ZWD_CONFIG_DIR"
  rm -rf "$ZWD_CONFIG_DIR"
fi

cat <<EOF

Uninstalled. Not removed:
  - your attachments in $data_dir
  - your backups
  - rclone and its config (~/.config/rclone)
EOF
[[ -n "$ZWD_LOG_DIR" ]] && echo "  - logs in $ZWD_LOG_DIR"
echo "Remember to switch Zotero's file syncing back to Zotero storage, or off."
