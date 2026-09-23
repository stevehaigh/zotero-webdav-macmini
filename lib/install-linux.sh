# shellcheck shell=bash
# Linux parts of install.sh (systemd): Raspberry Pi OS, Debian, Ubuntu.
# Sourced by install.sh, not run directly. Expects lib/common.sh to be loaded
# and REPO_DIR to be set.

install_prerequisites() {
  command -v systemctl >/dev/null 2>&1 || die "systemd not found. This installer needs a systemd-based distribution."
  command -v apt-get >/dev/null 2>&1 || warn "apt-get not found; install curl, unzip and htpasswd (apache2-utils) yourself if anything is missing."

  local model arch
  model="$(pi_model)"
  arch="$(uname -m)"
  [[ -n "$model" ]] && info "Detected $model ($arch)"
  [[ "$arch" == "aarch64" || "$arch" == "x86_64" ]] \
    || warn "Architecture $arch: a 64-bit OS (e.g. Raspberry Pi OS Lite 64-bit) is recommended."

  if command -v apt-get >/dev/null 2>&1; then
    local pkgs=()
    command -v curl     >/dev/null 2>&1 || pkgs+=(curl)
    command -v unzip    >/dev/null 2>&1 || pkgs+=(unzip)
    command -v htpasswd >/dev/null 2>&1 || pkgs+=(apache2-utils)
    if (( ${#pkgs[@]} )); then
      info "Installing ${pkgs[*]} (needs sudo)"
      { sudo apt-get update -qq && sudo apt-get install -y -qq "${pkgs[@]}"; } \
        || warn "Could not install ${pkgs[*]}; continuing (htpasswd falls back to openssl)."
    fi
  fi

  if ! command -v rclone >/dev/null 2>&1; then
    # Distribution packages of rclone are often years old, and the OneDrive
    # backend needs a recent version, so use rclone's own installer.
    info "Installing the latest rclone from rclone.org (needs sudo)"
    if ! curl -fsSL https://rclone.org/install.sh | sudo bash; then
      warn "rclone.org installer failed; falling back to the distribution package"
      sudo apt-get install -y -qq rclone
    fi
  fi
}

# Default backup destination: an rclone OneDrive remote (there is no OneDrive app for Linux).
default_backup_dest() { echo "onedrive:Backups/ZoteroDAV"; }

local_hostname() { hostname -s; }

# render <template> <dest>: fill in the __PLACEHOLDERS__ of a systemd unit.
render_unit() {
  sed -e "s|__USER__|$(id -un)|g" \
      -e "s|__GROUP__|$(id -gn)|g" \
      -e "s|__HOME__|$HOME|g" \
      -e "s|__PREFIX__|$ZWD_PREFIX|g" \
      -e "s|__BACKUP_TIME__|$(printf '%02d:%02d' "${BACKUP_HOUR:-3}" "${BACKUP_MINUTE:-30}")|g" \
      "$1" > "$2"
}

install_services() {
  local tmp unit
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  info "Installing systemd units (needs sudo)"
  for unit in "$ZWD_SERVER_UNIT" "$ZWD_BACKUP_UNIT" "$ZWD_BACKUP_TIMER"; do
    render_unit "$REPO_DIR/systemd/$unit" "$tmp/$unit"
    if command -v systemd-analyze >/dev/null 2>&1; then
      systemd-analyze verify "$tmp/$unit" 2>&1 | grep -v 'not found\|Unit .* not loaded' >&2 || true
    fi
    sudo install -m 644 -o root -g root "$tmp/$unit" "/etc/systemd/system/$unit"
  done
  sudo systemctl daemon-reload

  sudo systemctl enable "$ZWD_SERVER_UNIT" >/dev/null 2>&1
  sudo systemctl restart "$ZWD_SERVER_UNIT"

  if [[ -n "$BACKUP_DEST" ]]; then
    info "Enabling nightly backup timer ($(printf '%02d:%02d' "${BACKUP_HOUR:-3}" "${BACKUP_MINUTE:-30}"))"
    sudo systemctl enable --now "$ZWD_BACKUP_TIMER" >/dev/null 2>&1
  else
    sudo systemctl disable --now "$ZWD_BACKUP_TIMER" >/dev/null 2>&1 || true
  fi
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
    info "ufw firewall is active; allowing TCP port $PORT"
    sudo ufw allow "$PORT/tcp" comment 'zotero-webdav' >/dev/null
  fi
}

post_install_notes() {
  if [[ "$BACKUP_DEST" != /* ]] && [[ -n "$BACKUP_DEST" ]]; then
    local remote="${BACKUP_DEST%%:*}"
    if ! "$RCLONE" listremotes 2>/dev/null | grep -qxF "$remote:"; then
      cat <<EOF

Backups go to the rclone remote "$remote:", which isn't set up yet.
This machine has no browser, so authorise OneDrive on your Mac and paste the token:
  1. On the Mac:  brew install rclone && rclone authorize "onedrive"
     (sign in in the browser; copy the token it prints)
  2. Here:        rclone config
     n (new remote) > name: $remote > storage: onedrive > leave client_id/secret blank
     > "Use web browser to automatically authenticate?" n > paste the token
     > choose "OneDrive Personal" and your drive
  3. Test:        zwd-backup
Full details: docs/backup.md
EOF
    fi
  fi
  if ! find_tailscale >/dev/null; then
    cat <<EOF

To reach the server away from home, install Tailscale:
  curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up
EOF
  fi
}
