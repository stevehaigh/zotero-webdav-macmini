#!/bin/bash
# Remove the Zotero WebDAV services and scripts.
# Your attachment data (DATA_DIR) and backups are never touched.
#
#   ./uninstall.sh                remove services and scripts, keep config + password
#   ./uninstall.sh --purge-config also delete ~/.config/zotero-webdav
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
is_macos || die "This script is for macOS."

info "Stopping and removing the server LaunchDaemon (needs sudo)"
sudo launchctl bootout "system/$ZWD_SERVER_LABEL" 2>/dev/null || true
sudo rm -f "/Library/LaunchDaemons/$ZWD_SERVER_LABEL.plist"

info "Removing the backup LaunchAgent"
launchctl bootout "gui/$(id -u)/$ZWD_BACKUP_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$ZWD_BACKUP_LABEL.plist"

info "Removing scripts from $ZWD_PREFIX"
rm -rf "$ZWD_PREFIX"

if [[ "${1:-}" == "--purge-config" ]]; then
  info "Removing config and password from $ZWD_CONFIG_DIR"
  rm -rf "$ZWD_CONFIG_DIR"
fi

data_dir="$HOME/ZoteroDAV"
if [[ -f "$ZWD_CONFIG" ]]; then
  # shellcheck source=/dev/null
  data_dir="$(source "$ZWD_CONFIG"; echo "${DATA_DIR:-$HOME/ZoteroDAV}")"
fi
cat <<EOF

Uninstalled. Not removed:
  - your attachments in $data_dir
  - your backups in OneDrive
  - logs in $ZWD_LOG_DIR
  - rclone (brew uninstall rclone)
Remember to switch Zotero's file syncing back to Zotero storage, or off.
EOF
