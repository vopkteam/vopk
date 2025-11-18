#!/usr/bin/env bash
# APKG Installer - GP Team
# Installs apkg into /bin/apkg and prepares dependencies per distro.

set -euo pipefail

APKG_URL="https://raw.githubusercontent.com/gpteamofficial/apkg/main/apkg.sh"
APKG_DEST="/bin/apkg"

# ------------------ helpers ------------------

log() {
  printf '[apkg-installer] %s\n' "$*" >&2
}

fail() {
  printf '[apkg-installer][ERROR] %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "This installer must be run as root. Try: sudo $0"
  fi
}

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt-get"
    PKG_FAMILY="debian"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PKG_FAMILY="redhat"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    PKG_FAMILY="redhat"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
    PKG_FAMILY="suse"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_FAMILY="alpine"
  else
    PKG_MGR=""
    PKG_FAMILY=""
  fi
}

install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr

  if [ -z "${PKG_MGR}" ]; then
    fail "No supported package manager found to install curl (pacman/apt/dnf/yum/zypper/apk). Install curl or wget manually and rerun."
  fi

  log "Neither curl nor wget found. Installing curl using ${PKG_MGR}..."

  case "${PKG_FAMILY}" in
    debian)
      ${PKG_MGR} update -y || ${PKG_MGR} update || true
      ${PKG_MGR} install -y curl
      ;;
    arch)
      pacman -Sy --noconfirm curl
      ;;
    redhat)
      ${PKG_MGR} install -y curl
      ;;
    suse)
      zypper refresh || true
      zypper install -y curl
      ;;
    alpine)
      apk update || true
      apk add curl
      ;;
    *)
      fail "Unsupported package manager family '${PKG_FAMILY}' for installing curl."
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    fail "Failed to install curl. Please install curl or wget manually, then rerun."
  fi
}

download_apkg() {
  tmpfile="$(mktemp /tmp/apkg.XXXXXX.sh)"

  if command -v curl >/dev/null 2>&1; then
    log "Downloading APKG using curl..."
    curl -fsSL "${APKG_URL}" -o "${tmpfile}"
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading APKG using wget..."
    wget -qO "${tmpfile}" "${APKG_URL}"
  else
    fail "Neither curl nor wget available after installation step. Aborting."
  fi

  if [ ! -s "${tmpfile}" ]; then
    rm -f "${tmpfile}"
    fail "Downloaded file is empty. Check network or APKG_URL."
  fi

  echo "${tmpfile}"
}

install_apkg() {
  local src="$1"

  log "Installing APKG to ${APKG_DEST} ..."
  mkdir -p "$(dirname "${APKG_DEST}")"

  # Move script into place
  mv "${src}" "${APKG_DEST}"

  # Make executable
  chmod 0755 "${APKG_DEST}"

  log "APKG installed successfully at: ${APKG_DEST}"
}

print_summary() {
  cat <<EOF

APKG installation completed.

Binary location:
  ${APKG_DEST}

Basic usage:
  apkg help
  apkg update
  apkg full-upgrade
  apkg install <package>
  apkg remove <package>

APKG is a unified package manager interface by GP Team.
EOF
}

# ------------------ main ------------------

main() {
  require_root
  install_curl_if_needed

  tmpfile="$(download_apkg)"
  install_apkg "${tmpfile}"
  print_summary
}

main "$@"
