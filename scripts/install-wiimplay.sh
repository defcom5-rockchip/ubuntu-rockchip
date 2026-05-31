#!/usr/bin/env bash
#
# install-wiimplay.sh
#
# Personal post-install helper for the defcom5-rockchip ubuntu-rockchip fork.
# Builds and installs the wiimplay UPnP control point for WiiM streamers
# (https://github.com/shumatech/wiimplay) on the current user's account
# and registers a .desktop file so it appears in the application launcher.
#
# This script is NOT part of the base image. Run it on a per-machine,
# per-user basis after first boot.
#
# Usage:
#   bash install-wiimplay.sh
#
# Requirements:
#   - A working internet connection
#   - sudo privileges (for apt install of build dependencies)
#   - A graphical desktop session if you want the launcher icon to appear
#

set -euo pipefail

# ---------- configuration ----------
WIIMPLAY_REPO="https://github.com/shumatech/wiimplay.git"
BUILD_DIR="$(mktemp -d -t wiimplay-build-XXXXXX)"
INSTALL_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/wiimplay.desktop"
BINARY_NAME="wiimplay"

# ---------- helpers ----------
log()  { printf '\033[1;34m[wiimplay-install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[wiimplay-install]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[wiimplay-install]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -d "${BUILD_DIR}" ]]; then
    log "Cleaning up build directory: ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
  fi
}
trap cleanup EXIT

# ---------- sanity checks ----------
if [[ "${EUID}" -eq 0 ]]; then
  fail "Do not run this script as root. It installs to your user's home directory."
fi

if ! command -v sudo >/dev/null 2>&1; then
  fail "sudo is required to install build dependencies."
fi

# ---------- install build dependencies ----------
log "Installing build dependencies (requires sudo)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  golang-go \
  git \
  libgtk-3-dev \
  pkg-config \
  build-essential \
  upx-ucl

# ---------- clone and build ----------
log "Cloning wiimplay source..."
git clone --depth 1 "${WIIMPLAY_REPO}" "${BUILD_DIR}/wiimplay"

log "Building wiimplay (this can take a minute or two on an ARM SBC)..."
cd "${BUILD_DIR}/wiimplay"
if ! make; then
  warn "Make failed (likely just the upx step). Falling back to plain 'go build'..."
  go build -tags=gtk_3_10 .
fi

if [[ ! -x "${BINARY_NAME}" ]]; then
  fail "Build appears to have succeeded but no binary named '${BINARY_NAME}' was produced. Aborting."
fi

# ---------- install binary ----------
log "Installing binary to ${INSTALL_DIR}/${BINARY_NAME}"
mkdir -p "${INSTALL_DIR}"
install -m 0755 "${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"

# ---------- create .desktop file ----------
log "Creating launcher entry at ${DESKTOP_FILE}"
mkdir -p "${DESKTOP_DIR}"
cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=WiiM Play
GenericName=Music Streamer Controller
Comment=UPnP control point for WiiM music streamers
Exec=${INSTALL_DIR}/${BINARY_NAME}
Icon=multimedia-audio-player
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupNotify=true
Keywords=wiim;upnp;dlna;music;audio;streamer;
EOF

# ---------- refresh desktop database ----------
if command -v update-desktop-database >/dev/null 2>&1; then
  log "Refreshing desktop database..."
  update-desktop-database "${DESKTOP_DIR}" || true
else
  warn "update-desktop-database not found — launcher may take a few minutes or a logout/login to appear."
fi

# ---------- ensure ~/.local/bin is on PATH ----------
if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
  warn "${INSTALL_DIR} is not on your PATH."
  warn "Add this to your ~/.bashrc or ~/.profile to fix:"
  warn "    export PATH=\"\${HOME}/.local/bin:\${PATH}\""
  warn "Then either open a new terminal or run: source ~/.bashrc"
fi

# ---------- done ----------
log "Installation complete."
log ""
log "  Binary:    ${INSTALL_DIR}/${BINARY_NAME}"
log "  Launcher:  ${DESKTOP_FILE}"
log ""
log "Launch from the application menu (search 'wiim'), or run '${BINARY_NAME}' from a terminal."
log "To pin to your dock: open the app, right-click its dock icon, choose 'Add to Favorites'."
