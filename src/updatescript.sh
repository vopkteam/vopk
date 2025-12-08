#!/usr/bin/env sh
# VOPK Installer + Maintenance - GP Team
# - Polite confirmation before doing anything (unless -y)
# - On Arch: temporary 'aurbuild' user to install yay, then cleanup
# - Colored output via printf
# - POSIX sh compatible
#
# Designed to work reliably even when piped, e.g.:
#   curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopkg/main/updatescript.sh | sudo sh

set -eu

VOPK_URL="https://raw.githubusercontent.com/gpteamofficial/vopkg/main/bin/vopk"
VOPK_DEST="/usr/local/bin/vopk"
VOPK_BAK="/usr/local/bin/vopk.bak"

PKG_MGR=""
PKG_FAMILY=""
AUR_USER_CREATED=0
AUTO_YES=0
CMD=""

# ------------------ colors (TTY-safe) ------------------

if [ -t 2 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  C_RESET="$(printf '\033[0m')"
  C_INFO="$(printf '\033[1;34m')"  # blue
  C_WARN="$(printf '\033[1;33m')"  # yellow
  C_ERR="$(printf '\033[1;31m')"   # red
  C_OK="$(printf '\033[1;32m')"    # green
else
  C_RESET=''
  C_INFO=''
  C_WARN=''
  C_ERR=''
  C_OK=''
fi

# ------------------ helpers ------------------

log() {
  printf '%s[vopk-installer]%s %s\n' "$C_INFO" "$C_RESET" "$*" >&2
}

warn() {
  printf '%s[vopk-installer][WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2
}

ok() {
  printf '%s[vopk-installer][OK]%s %s\n' "$C_OK" "$C_RESET" "$*" >&2
}

fail() {
  printf '%s[vopk-installer][ERROR]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
  exit 1
}

log_install() {
  printf '%s[vopk-installer][INSTALL]%s %s\n' "$C_OK" "$C_RESET" "$*" >&2
}

log_delete_msg() {
  printf '%s[vopk-installer][DELETE]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
}

usage() {
  printf 'Usage: %s [OPTIONS] [COMMAND]\n' "$0"
  printf '\nOptions:\n'
  printf '  -y, --yes, --assume-yes   Run non-interactively (assume "yes" to prompts)\n'
  printf '  -h, --help                Show this help and exit\n'
  printf '\nCommands:\n'
  printf '  install       Fresh install of VOPK\n'
  printf '  update        Update existing VOPK (or install if missing)\n'
  printf '  reinstall     Remove and install again\n'
  printf '  repair        Check/fix VOPK binary\n'
  printf '  delete        Delete VOPK (keep backup if exists)\n'
  printf '  delete-all    Delete VOPK and backup\n'
  printf '  menu          Show interactive menu (default)\n'
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root. Try: sudo sh $0"
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

# Always try /dev/tty for interactive input to avoid fighting with pipes.
# If /dev/tty is not available or read fails, we treat it as non-interactive.
read_from_tty() {
  # $1: variable name to assign into
  varname=$1
  if [ -r /dev/tty ]; then
    # suppress "read error" noise if TTY is not usable
    if IFS= read -r "$varname" 2>/dev/null </dev/tty; then
      return 0
    fi
  fi
  return 1
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

  printf '%s[vopk-installer][PROMPT]%s %s %s ' "$C_WARN" "$C_RESET" "$msg" "$prompt" >&2

  ans=""
  if ! read_from_tty ans; then
    # No usable TTY: be safe and treat as "no"
    printf '\n' >&2
    warn "No interactive terminal available; assuming NO."
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
      if [ "$PKG_MGR" = "apt-get" ]; then
        "$PKG_MGR" update -y 2>/dev/null || "$PKG_MGR" update || true
        "$PKG_MGR" install -y curl
      else
        "$PKG_MGR" update 2>/dev/null || true
        "$PKG_MGR" install curl
      fi
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
      apk add --no-cache curl
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

download_vopk() {
  tmpfile="$(mktemp /tmp/vopk.XXXXXX.sh)"

  if command -v curl >/dev/null 2>&1; then
    log "Downloading VOPK using curl..."
    if ! curl -fsSL "$VOPK_URL" -o "$tmpfile"; then
      rm -f "$tmpfile"
      fail "Failed to download VOPK (curl)."
    fi
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading VOPK using wget..."
    if ! wget -qO "$tmpfile" "$VOPK_URL"; then
      rm -f "$tmpfile"
      fail "Failed to download VOPK (wget)."
    fi
  else
    rm -f "$tmpfile"
    fail "Neither curl nor wget available after installation step. Aborting."
  fi

  if [ ! -s "$tmpfile" ]; then
    rm -f "$tmpfile"
    fail "Downloaded file is empty. Check network or VOPK_URL."
  fi

  ok "VOPK script downloaded to temporary file."
  printf '%s\n' "$tmpfile"
}

install_vopk() {
  src=$1

  log_install "Installing VOPK to ${VOPK_DEST} ..."
  mkdir -p "$(dirname "$VOPK_DEST")"

  if [ -f "$VOPK_DEST" ]; then
    log_install "Backing up existing VOPK to ${VOPK_BAK}"
    cp -f "$VOPK_DEST" "$VOPK_BAK" || true
  fi

  mv "$src" "$VOPK_DEST"
  chmod 0755 "$VOPK_DEST"

  log_install "VOPK installed successfully at: ${VOPK_DEST}"
}

print_summary() {
  printf '\n%sVOPK installation completed.%s\n\n' "$C_OK" "$C_RESET"
  printf 'Binary location:\n  %s\n\n' "$VOPK_DEST"
  printf 'Basic usage:\n'
  printf '  vopk help\n'
  printf '  vopk update\n'
  printf '  vopk full-upgrade\n'
  printf '  vopk install <package>\n'
  printf '  vopk remove <package>\n\n'
  printf 'VOPK is a unified package manager interface by GP Team.\n'
}

install_yay_arch() {
  if ! command -v pacman >/dev/null 2>&1; then
    return 0
  fi

  if command -v yay >/dev/null 2>&1; then
    ok "Detected 'yay' already installed; skipping AUR helper installation."
    return 0
  fi

  log_install "Preparing temporary AUR build user 'aurbuild' to install yay..."

  if id -u aurbuild >/dev/null 2>&1; then
    warn "User 'aurbuild' already exists; will reuse it and NOT remove it afterwards."
    AUR_USER_CREATED=0
  else
    useradd -m -r -s /bin/bash aurbuild
    AUR_USER_CREATED=1
    ok "Temporary user 'aurbuild' created."
  fi

  log_install "Ensuring base-devel and git are installed via pacman..."
  pacman -Sy --needed --noconfirm base-devel git

  log_install "Switching to 'aurbuild' to build and install yay from AUR..."
  su - aurbuild <<'EOF'
set -eu
workdir="$(mktemp -d /tmp/yay.XXXXXX)"
cd "$workdir"
git clone --depth=1 https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
EOF

  ok "yay has been installed."

  if [ "$AUR_USER_CREATED" -eq 1 ]; then
    log_install "Cleaning up temporary user 'aurbuild' and its home directory..."
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
  log_install "Starting VOPK fresh installation ..."
  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_vopk)"
  install_vopk "$tmpfile"
  print_summary
}

op_update() {
  if [ ! -f "$VOPK_DEST" ]; then
    log_install "VOPK not found at ${VOPK_DEST}. Performing fresh install instead of update."
    op_install
    return
  fi

  log_install "Updating existing VOPK at ${VOPK_DEST} ..."
  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_vopk)"
  install_vopk "$tmpfile"
  log_install "Update completed."
}

op_reinstall() {
  log_install "Reinstalling VOPK ..."

  if [ -f "$VOPK_DEST" ]; then
    log_install "Removing existing VOPK at ${VOPK_DEST}"
    rm -f "$VOPK_DEST"
  fi

  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_vopk)"
  install_vopk "$tmpfile"
  log_install "Reinstall completed."
}

op_repair() {
  log "Repairing VOPK installation ..."

  install_curl_if_needed

  needs_fix=0

  if [ ! -f "$VOPK_DEST" ]; then
    log "VOPK binary missing."
    needs_fix=1
  elif [ ! -s "$VOPK_DEST" ]; then
    log "VOPK binary is empty."
    needs_fix=1
  elif [ ! -x "$VOPK_DEST" ]; then
    log "VOPK binary is not executable. Fixing permissions..."
    if chmod 0755 "$VOPK_DEST"; then
      :
    else
      needs_fix=1
    fi
  fi

  if [ -f "$VOPK_DEST" ] && ! head -n 1 "$VOPK_DEST" | grep -q "bash"; then
    log "VOPK binary does not look like a shell script. Replacing..."
    needs_fix=1
  fi

  if [ "$needs_fix" -eq 1 ]; then
    log_install "Re-downloading VOPK to repair installation..."
    if [ "$PKG_FAMILY" = "arch" ]; then
      install_yay_arch
    fi
    tmpfile="$(download_vopk)"
    install_vopk "$tmpfile"
  else
    log "VOPK binary looks fine. No reinstall needed."
  fi

  log "Repair step finished."
}

op_delete() {
  log_delete_msg "Deleting VOPK ..."

  if [ -f "$VOPK_DEST" ]; then
    log_delete_msg "Removing ${VOPK_DEST}"
    rm -f "$VOPK_DEST"
  else
    log_delete_msg "VOPK not found at ${VOPK_DEST}. Nothing to delete."
  fi

  log_delete_msg "Delete operation completed (backup kept at ${VOPK_BAK} if exists)."
}

op_delete_all() {
  log_delete_msg "Deleting VOPK and backup ..."

  if [ -f "$VOPK_DEST" ]; then
    log_delete_msg "Removing ${VOPK_DEST}"
    rm -f "$VOPK_DEST"
  else
    log_delete_msg "VOPK not found at ${VOPK_DEST}."
  fi

  if [ -f "$VOPK_BAK" ]; then
    log_delete_msg "Removing backup ${VOPK_BAK}"
    rm -f "$VOPK_BAK"
  else
    log_delete_msg "No backup file ${VOPK_BAK} found."
  fi

  log_delete_msg "Delete + backup operation completed."
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
      log "  - Download latest VOPK from: $VOPK_URL"
      log "  - Backup existing VOPK to:   $VOPK_BAK (if present)"
      log "  - Install VOPK to:           $VOPK_DEST"
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Create temporary user 'aurbuild' to install yay, then clean it up."
      fi
      ;;
    update)
      log "Planned actions for UPDATE:"
      log "  - Ensure curl or wget is installed."
      log "  - Download latest VOPK from: $VOPK_URL"
      log "  - Backup current VOPK to:    $VOPK_BAK"
      log "  - Replace existing VOPK at:  $VOPK_DEST"
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Ensure yay is installed via temporary 'aurbuild' user if needed."
      fi
      ;;
    reinstall)
      log "Planned actions for REINSTALL:"
      log "  - Remove existing VOPK at:   $VOPK_DEST (if present)"
      log "  - Ensure curl or wget is installed."
      log "  - Download latest VOPK from: $VOPK_URL"
      log "  - Install VOPK to:           $VOPK_DEST"
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Ensure yay is installed via temporary 'aurbuild' user if needed."
      fi
      ;;
    repair)
      log "Planned actions for REPAIR:"
      log "  - Check VOPK binary at:      $VOPK_DEST"
      log "  - Fix permissions if needed."
      log "  - Re-download VOPK if binary missing/corrupt."
      if [ "$PKG_FAMILY" = "arch" ]; then
        log "  - (Arch) Ensure yay is installed via temporary 'aurbuild' user if repair requires reinstall."
      fi
      ;;
    delete)
      log "Planned actions for DELETE:"
      log "  - Remove VOPK at:            $VOPK_DEST (if present)"
      log "  - Keep backup at:            $VOPK_BAK (if present)"
      ;;
    delete-all)
      log "Planned actions for DELETE-ALL:"
      log "  - Remove VOPK at:            $VOPK_DEST (if present)"
      log "  - Remove backup at:          $VOPK_BAK (if present)"
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

  log "Welcome to the VOPK installer & maintenance tool."

  # Non-interactive mode with explicit command:
  #   curl .../updatescript.sh | sudo sh -s -- -y update
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

  choice=""
  if ! read_from_tty choice; then
    printf '\n' >&2
    fail "No interactive TTY available. Run with an explicit command, for example:
  curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopkg/main/updatescript.sh | sudo sh -s -- -y update"
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
