# shellcheck shell=bash disable=SC2034
# Shared helpers for the zotero-webdav scripts. Sourced, not executed.
# Works on macOS (launchd) and Linux/Raspberry Pi OS (systemd).

# Service names
ZWD_SERVER_LABEL="io.github.stevehaigh.zotero-webdav"         # macOS LaunchDaemon
ZWD_BACKUP_LABEL="io.github.stevehaigh.zotero-webdav-backup"  # macOS LaunchAgent
ZWD_SERVER_UNIT="zotero-webdav.service"                       # Linux systemd
ZWD_BACKUP_UNIT="zotero-webdav-backup.service"
ZWD_BACKUP_TIMER="zotero-webdav-backup.timer"

ZWD_CONFIG_DIR="${ZWD_CONFIG_DIR:-$HOME/.config/zotero-webdav}"
ZWD_CONFIG="${ZWD_CONFIG:-$ZWD_CONFIG_DIR/config.env}"
ZWD_PREFIX="${ZWD_PREFIX:-$HOME/.local/share/zotero-webdav}"
if [[ "$(uname -s)" == "Darwin" ]]; then
  ZWD_LOG_DIR="${ZWD_LOG_DIR:-$HOME/Library/Logs/zotero-webdav}"
else
  ZWD_LOG_DIR="${ZWD_LOG_DIR:-}"   # Linux: logs go to the systemd journal
fi

log()  { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

# Raspberry Pi model string, e.g. "Raspberry Pi 3 Model B Rev 1.2" (empty elsewhere).
pi_model() { [[ -r /proc/device-tree/model ]] && tr -d '\0' < /proc/device-tree/model || true; }

# Where to look for logs, for use in messages. $1 = server | backup
log_hint() {
  if is_macos; then
    echo "$ZWD_LOG_DIR/$1.log"
  elif [[ "$1" == server ]]; then
    echo "journalctl -u $ZWD_SERVER_UNIT"
  else
    echo "journalctl -u $ZWD_BACKUP_UNIT"
  fi
}

# Load config.env and apply defaults for anything left unset.
load_config() {
  [[ -f "$ZWD_CONFIG" ]] || die "Config not found at $ZWD_CONFIG. Run install.sh first."
  # shellcheck source=/dev/null
  source "$ZWD_CONFIG"
  DATA_DIR="${DATA_DIR:-$HOME/ZoteroDAV}"
  REQUIRE_MOUNTPOINT="${REQUIRE_MOUNTPOINT:-}"
  BIND_ADDR="${BIND_ADDR:-}"
  PORT="${PORT:-8080}"
  HTPASSWD_FILE="${HTPASSWD_FILE:-$ZWD_CONFIG_DIR/htpasswd}"
  RCLONE_BIN="${RCLONE_BIN:-$(command -v rclone || true)}"
  LOG_LEVEL="${LOG_LEVEL:-NOTICE}"
  BACKUP_DEST="${BACKUP_DEST:-}"
  BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-90}"
  [[ -n "$RCLONE_BIN" && -x "$RCLONE_BIN" ]] || die "rclone not found (RCLONE_BIN='$RCLONE_BIN'). Re-run install.sh."
}

# Print the mount point that holds <path> (using its nearest existing ancestor).
mount_point_of() {
  local p="$1"
  while [[ ! -e "$p" ]]; do p="$(dirname "$p")"; done
  df -P "$p" | awk 'NR==2 { for (i = 6; i <= NF; i++) printf "%s%s", $i, (i < NF ? " " : "") }'
}

# True if <dir> is itself a mounted filesystem (e.g. an external drive is plugged in).
is_mounted() {
  [[ -d "$1" ]] || return 1
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$1"
  else
    [[ "$(mount_point_of "$1")" == "$1" ]]
  fi
}

# Refuse to continue if the data drive is configured but not mounted. Serving or
# backing up an empty folder would make Zotero (or the backup) think every file
# had been deleted.
require_data_mount() {
  [[ -z "$REQUIRE_MOUNTPOINT" ]] && return 0
  is_mounted "$REQUIRE_MOUNTPOINT" && return 0
  die "Data drive $REQUIRE_MOUNTPOINT is not mounted. Refusing to run against an empty folder."
}

# Restart the WebDAV server if it is installed as a service.
restart_server() {
  if is_macos && [[ -f "/Library/LaunchDaemons/$ZWD_SERVER_LABEL.plist" ]]; then
    info "Restarting the WebDAV server (needs sudo)"
    sudo launchctl kickstart -k "system/$ZWD_SERVER_LABEL"
  elif is_linux && [[ -f "/etc/systemd/system/$ZWD_SERVER_UNIT" ]]; then
    info "Restarting the WebDAV server (needs sudo)"
    sudo systemctl restart "$ZWD_SERVER_UNIT"
  fi
}

# Locate the Tailscale CLI (Homebrew, standalone or App Store install, or Linux package).
find_tailscale() {
  local c
  for c in "$(command -v tailscale 2>/dev/null)" \
           /Applications/Tailscale.app/Contents/MacOS/Tailscale; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# Run the Tailscale CLI; on Linux, changing settings needs root.
tailscale_run() {
  local ts
  ts="$(find_tailscale)" || return 1
  if is_linux && [[ $EUID -ne 0 ]]; then sudo "$ts" "$@"; else "$ts" "$@"; fi
}

# Print this machine's Tailscale MagicDNS name (without trailing dot), if any.
tailscale_dns_name() {
  local ts
  ts="$(find_tailscale)" || return 1
  "$ts" status --json 2>/dev/null \
    | sed -n 's/.*"DNSName": *"\([^"]*\)\.".*/\1/p' | head -n 1
}
