# shellcheck shell=bash disable=SC2034
# Shared helpers for the zotero-webdav scripts. Sourced, not executed.

ZWD_SERVER_LABEL="io.github.stevehaigh.zotero-webdav"
ZWD_BACKUP_LABEL="io.github.stevehaigh.zotero-webdav-backup"
ZWD_CONFIG_DIR="${ZWD_CONFIG_DIR:-$HOME/.config/zotero-webdav}"
ZWD_CONFIG="${ZWD_CONFIG:-$ZWD_CONFIG_DIR/config.env}"
ZWD_PREFIX="${ZWD_PREFIX:-$HOME/.local/share/zotero-webdav}"
ZWD_LOG_DIR="${ZWD_LOG_DIR:-$HOME/Library/Logs/zotero-webdav}"

log()  { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

# Load config.env and apply defaults for anything left unset.
load_config() {
  [[ -f "$ZWD_CONFIG" ]] || die "Config not found at $ZWD_CONFIG. Run install.sh first."
  # shellcheck source=/dev/null
  source "$ZWD_CONFIG"
  DATA_DIR="${DATA_DIR:-$HOME/ZoteroDAV}"
  BIND_ADDR="${BIND_ADDR:-}"
  PORT="${PORT:-8080}"
  HTPASSWD_FILE="${HTPASSWD_FILE:-$ZWD_CONFIG_DIR/htpasswd}"
  RCLONE_BIN="${RCLONE_BIN:-$(command -v rclone || true)}"
  LOG_LEVEL="${LOG_LEVEL:-NOTICE}"
  BACKUP_DEST="${BACKUP_DEST:-}"
  BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-90}"
  [[ -n "$RCLONE_BIN" && -x "$RCLONE_BIN" ]] || die "rclone not found (RCLONE_BIN='$RCLONE_BIN'). Install it with: brew install rclone"
}

# Restart the WebDAV LaunchDaemon if it is installed.
restart_server() {
  is_macos || return 0
  if [[ -f "/Library/LaunchDaemons/$ZWD_SERVER_LABEL.plist" ]]; then
    info "Restarting the WebDAV server (needs sudo)"
    sudo launchctl kickstart -k "system/$ZWD_SERVER_LABEL"
  fi
}

# Locate the Tailscale CLI (Homebrew, standalone or App Store install).
find_tailscale() {
  local c
  for c in "$(command -v tailscale 2>/dev/null)" \
           /Applications/Tailscale.app/Contents/MacOS/Tailscale; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# Print this machine's Tailscale MagicDNS name (without trailing dot), if any.
tailscale_dns_name() {
  local ts
  ts="$(find_tailscale)" || return 1
  "$ts" status --json 2>/dev/null \
    | sed -n 's/.*"DNSName": *"\([^"]*\)\.".*/\1/p' | head -n 1
}
