#!/usr/bin/env sh
# APKG Installer + Maintenance - GP Team (modded)
# - Polite confirmation before doing anything (unless -y)
# - On Arch: temporary 'aurbuild' user to install yay, then cleanup
# - Colored output via printf
# - POSIX sh compatible

set -eu

APKG_URL="https://raw.githubusercontent.com/gpteamofficial/apkg/main/apkg"
APKG_DEST="/bin/apkg"
APKG_BAK="/bin/apkg.bak"

PKG_MGR=""
PKG_FAMILY=""
AUR_USER_CREATED=0
AUTO_YES=0
CMD=""

# ------------------ colors (TTY-safe) ------------------

if [ -t 2 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  C_RESET='\033[0m'
  C_INFO='\033[1;34m'
  C_WARN='\033[1;33m'
  C_ERR='\033[1;31m'
  C_OK='\033[1;32m'
else
  C_RESET=''
  C_INFO=''
  C_WARN=''
  C_ERR=''
  C_OK=''
fi

# ------------------ helpers ------------------

log() {
  printf '%s[apkg-installer]%s %s\n' "$C_INFO" "$C_RESET" "$*" >&2
}

warn() {
  printf '%s[apkg-installer][WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2
}

ok() {
  printf '%s[apkg-installer][OK]%s %s\n' "$C_OK" "$C_RESET" "$*" >&2
}

fail() {
  printf '%s[apkg-installer][ERROR]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s [OPTIONS] [COMMAND]\n' "$0"
  printf '\nOptions:\n'
  printf '  -y, --yes, --assume-yes   Run non-interactively (assume "yes" to prompts)\n'
  printf '  -h, --help                Show this help and exit\n'
  printf '\nCommands:\n'
  printf '  install       Fresh install of APKG\n'
  printf '  update        Update existing APKG (or install if missing)\n'
  printf '  reinstall     Remove and install again\n'
  printf '  repair        Check/fix APKG binary\n'
  printf '  delete        Delete APKG (keep backup if exists)\n'
  printf '  delete-all    Delete APKG and backup\n'
  printf '  menu          Show interactive menu (default)\n'
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root. Try: sudo $0"
  fi
}

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt-get"
    PKG_FAMILY="debian"
  elif command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
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

ask_confirmation() {
  # $1 = message, $2 = default (Y/N, optional, default N)
  msg=$1
  default=${2:-N}

  if [ "$AUTO_YES" -eq 1 ]; then
    log "AUTO_YES enabled; auto-confirming: $msg"
    return 0
  fi

  case "$default" in
    Y|y)
      prompt="[Y/n]"
      def="Y"
      ;;
    *)
      prompt="[y/N]"
      def="N"
      ;;
  esac

  printf '%s[apkg-installer][PROMPT]%s %s %s ' "$C_WARN" "$C_RESET" "$msg" "$prompt" >&2
  if ! read -r ans; then
    return 1
  fi

  if [ -z "$ans" ]; then
    ans="$def"
  fi

  case "$ans" in
    Y|y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr

  if [ -z "$PKG_MGR" ]; then
    fail "No supported package manager found to install curl (pacman/apt/dnf/yum/zypper/apk). Install curl or wget manually and rerun."
  fi

  log "Neither curl nor wget found. Installing curl using ${PKG_MGR}..."

  case "$PKG_FAMILY" in
    debian)
      "$PKG_MGR" update -y 2>/dev/null || "$PKG_MGR" update || true
      "$PKG_MGR" install -y curl
      ;;
    arch)
      pacman -Sy --noconfirm curl
      ;;
    redhat)
      "$PKG_MGR" install -y curl
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

  ok "curl (or wget) is now available."
}

download_apkg() {
  tmpfile="$(mktemp /tmp/apkg.XXXXXX.sh)"

  if command -v curl >/dev/null 2>&1; then
    log "Downloading APKG using curl..."
    if ! curl -fsSL "$APKG_URL" -o "$tmpfile"; then
      rm -f "$tmpfile"
      fail "Failed to download APKG (curl)."
    fi
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading APKG using wget..."
    if ! wget -qO "$tmpfile" "$APKG_URL"; then
      rm -f "$tmpfile"
      fail "Failed to download APKG (wget)."
    fi
  else
    rm -f "$tmpfile"
    fail "Neither curl nor wget available after installation step. Aborting."
  fi

  if [ ! -s "$tmpfile" ]; then
    rm -f "$tmpfile"
    fail "Downloaded file is empty. Check network or APKG_URL."
  fi

  ok "APKG script downloaded to temporary file."
  printf '%s\n' "$tmpfile"
}

install_apkg() {
  src=$1

  log "Installing APKG to ${APKG_DEST} ..."
  mkdir -p "$(dirname "$APKG_DEST")"

  if [ -f "$APKG_DEST" ]; then
    log "Backing up existing APKG to ${APKG_BAK}"
    cp -f "$APKG_DEST" "$APKG_BAK" || true
  fi

  mv "$src" "$APKG_DEST"
  chmod 0755 "$APKG_DEST"

  ok "APKG installed successfully at: ${APKG_DEST}"
}

print_summary() {
  printf '\n%sAPKG installation completed.%s\n\n' "$C_OK" "$C_RESET"
  printf 'Binary location:\n  %s\n\n' "$APKG_DEST"
  printf 'Basic usage:\n'
  printf '  apkg help\n'
  printf '  apkg update\n'
  printf '  apkg full-upgrade\n'
  printf '  apkg install <package>\n'
  printf '  apkg remove <package>\n\n'
  printf 'APKG is a unified package manager interface by GP Team.\n'
}

install_yay_arch() {
  # Only for Arch-like systems with pacman
  if ! command -v pacman >/dev/null 2>&1; then
    return 0
  fi

  if command -v yay >/dev/null 2>&1; then
    ok "Detected 'yay' already installed; skipping AUR helper installation."
    return 0
  fi

  log "Preparing temporary AUR build user 'aurbuild' to install yay..."

  if id -u aurbuild >/dev/null 2>&1; then
    warn "User 'aurbuild' already exists; will reuse it and NOT remove it afterwards."
    AUR_USER_CREATED=0
  else
    useradd -m -r -s /bin/bash aurbuild
    AUR_USER_CREATED=1
    ok "Temporary user 'aurbuild' created."
  fi

  log "Ensuring base-devel and git are installed via pacman..."
  pacman -Sy --needed --noconfirm base-devel git

  log "Switching to 'aurbuild' to build and install yay from AUR..."
  su - aurbuild -c '
    set -eu
    workdir=$(mktemp -d /tmp/yay.XXXXXX)
    cd "$workdir"
    git clone --depth=1 https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
  '

  ok "yay has been installed."

  if [ "$AUR_USER_CREATED" -eq 1 ]; then
    log "Cleaning up temporary user 'aurbuild' and its home directory..."
    if userdel -r aurbuild 2>/dev/null; then
      ok "Temporary user 'aurbuild' removed."
    else
      warn "Failed to remove user 'aurbuild'; please remove it manually if not needed."
    fi
  else
    warn "Not removing existing 'aurbuild' user (it existed before running this script)."
  fi

  ok "Returned from temporary user; continuing as root."
}

# ------------------ operations ------------------

op_install() {
  log "Starting APKG fresh installation ..."
  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_apkg)"
  install_apkg "$tmpfile"
  print_summary
}

op_update() {
  if [ ! -f "$APKG_DEST" ]; then
    log "APKG not found at ${APKG_DEST}. Performing fresh install instead of update."
    op_install
    return
  fi

  log "Updating existing APKG at ${APKG_DEST} ..."
  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_apkg)"
  install_apkg "$tmpfile"
  log "Update completed."
}

op_reinstall() {
  log "Reinstalling APKG ..."

  if [ -f "$APKG_DEST" ]; then
    log "Removing existing APKG at ${APKG_DEST}"
    rm -f "$APKG_DEST"
  fi

  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_apkg)"
  install_apkg "$tmpfile"
  log "Reinstall completed."
}

op_repair() {
  log "Repairing APKG installation ..."

  install_curl_if_needed

  needs_fix=0

  if [ ! -f "$APKG_DEST" ]; then
    log "APKG binary missing."
    needs_fix=1
  elif [ ! -s "$APKG_DEST" ]; then
    log "APKG binary is empty."
    needs_fix=1
  elif [ ! -x "$APKG_DEST" ]; then
    log "APKG binary is not executable. Fixing permissions..."
    if chmod 0755 "$APKG_DEST"; then
      :
    else
      needs_fix=1
    fi
  fi

  if [ -f "$APKG_DEST" ] && ! head -n 1 "$APKG_DEST" | grep -q "bash"; then
    log "APKG binary does not look like a shell script. Replacing..."
    needs_fix=1
  fi

  if [ "$needs_fix" -eq 1 ]; then
    log "Re-downloading APKG to repair installation..."
    if [ "$PKG_FAMILY" = "arch" ]; then
      install_yay_arch
    fi
    tmpfile="$(download_apkg)"
    install_apkg "$tmpfile"
  else
    log "APKG binary looks fine. No reinstall needed."
  fi

  log "Repair step finished."
}

op_delete() {
  log "Deleting APKG ..."

  if [ -f "$APKG_DEST" ]; then
    rm -f "$APKG_DEST"
    log "Removed ${APKG_DEST}"
  else
    log "APKG not found at ${APKG_DEST}. Nothing to delete."
  fi

  log "Delete operation completed (backup kept at ${APKG_BAK} if exists)."
}

op_delete_all() {
  log "Deleting APKG and backup ..."

  if [ -f "$APKG_DEST" ]; then
    rm -f "$APKG_DEST"
    log "Removed ${APKG_DEST}"
  else
    log "APKG not found at ${APKG_DEST}."
  fi

  if [ -f "$APKG_BAK" ]; then
    rm -f "$APKG_BAK"
    log "Removed backup ${APKG_BAK}"
  else
    log "No backup file ${APKG_BAK} found."
  fi

  log "Delete + backup operation completed."
}

# ------------------ menu ------------------

show_menu() {
  printf 'Choose What You Want To Do:\n\n'
  printf '  1) Repair\n'
  printf '  2) Reinstall\n'
  printf '  3) Delete\n'
  printf '  4) Delete and delete backup\n'
  printf '  5) Update\n\n'
  printf '  0) Exit\n'
  printf '[INPUT] ->: '
}

# ------------------ describe & confirm ------------------

describe_and_confirm() {
  op=$1

  case "$op" in
    install)
      log "Planned actions for INSTALL:"
      log "  - Ensure curl or wget is installed."
      log "  - Download latest APKG from: $APKG_URL"
      log "  - Backup existing APKG to:  $APKG_BAK (if present)"
      log "  - Install APKG to:          $APKG_DEST"
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Create temporary user 'aurbuild' to install yay, then clean it up."
      fi
      ;;
    update)
      log "Planned actions for UPDATE:"
      log "  - Ensure curl or wget is installed."
      log "  - Download latest APKG from: $APKG_URL"
      log "  - Backup current APKG to:    $APKG_BAK"
      log "  - Replace existing APKG at:  $APKG_DEST"
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Ensure yay is installed via temporary 'aurbuild' user if needed."
      fi
      ;;
    reinstall)
      log "Planned actions for REINSTALL:"
      log "  - Remove existing APKG at:   $APKG_DEST (if present)"
      log "  - Ensure curl or wget is installed."
      log "  - Download latest APKG from: $APKG_URL"
      log "  - Install APKG to:           $APKG_DEST"
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Ensure yay is installed via temporary 'aurbuild' user if needed."
      fi
      ;;
    repair)
      log "Planned actions for REPAIR:"
      log "  - Check APKG binary at:      $APKG_DEST"
      log "  - Fix permissions if needed."
      log "  - Re-download APKG if binary missing/corrupt."
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Ensure yay is installed via temporary 'aurbuild' user if repair requires reinstall."
      fi
      ;;
    delete)
      log "Planned actions for DELETE:"
      log "  - Remove APKG at:            $APKG_DEST (if present)"
      log "  - Keep backup at:            $APKG_BAK (if present)"
      ;;
    delete-all)
      log "Planned actions for DELETE-ALL:"
      log "  - Remove APKG at:            $APKG_DEST (if present)"
      log "  - Remove backup at:          $APKG_BAK (if present)"
      ;;
    *)
      ;;
  esac

  if ! ask_confirmation "Do you want to continue with this operation?" "N"; then
    warn "Operation aborted by user; nothing was changed."
    exit 0
  fi
}

# ------------------ args parsing ------------------

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes|--assume-yes)
        AUTO_YES=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      install|update|reinstall|repair|delete|remove|uninstall|delete-all|delete_all|menu)
        CMD="$1"
        ;;
      *)
        warn "Unknown option or command: $1"
        ;;
    esac
    shift
  done
}

# ------------------ main ------------------

main() {
  parse_args "$@"
  require_root
  detect_pkg_mgr

  log "Welcome to the APKG installer & maintenance tool."

  if [ -n "$CMD" ] && [ "$CMD" != "menu" ]; then
    case "$CMD" in
      install)
        describe_and_confirm "install"
        op_install
        ;;
      update)
        describe_and_confirm "update"
        op_update
        ;;
      reinstall)
        describe_and_confirm "reinstall"
        op_reinstall
        ;;
      repair)
        describe_and_confirm "repair"
        op_repair
        ;;
      delete|remove|uninstall)
        describe_and_confirm "delete"
        op_delete
        ;;
      delete-all|delete_all)
        describe_and_confirm "delete-all"
        op_delete_all
        ;;
      *)
        fail "Unknown command '$CMD'."
        ;;
    esac
    exit 0
  fi

  # interactive menu (default behavior)
  show_menu

  if [ -t 0 ]; then
    read -r choice
  elif [ -r /dev/tty ]; then
    read -r choice </dev/tty
  else
    fail "No interactive terminal available to read input."
  fi

  case "$choice" in
    1)
      describe_and_confirm "repair"
      op_repair
      ;;
    2)
      describe_and_confirm "reinstall"
      op_reinstall
      ;;
    3)
      describe_and_confirm "delete"
      op_delete
      ;;
    4)
      describe_and_confirm "delete-all"
      op_delete_all
      ;;
    5)
      describe_and_confirm "update"
      op_update
      ;;
    0)
      log "Exiting..."
      exit 0
      ;;
    *)
      fail "Invalid choice '${choice}'. Please run again and choose between 0-5."
      ;;
  esac
}

main "$@"
