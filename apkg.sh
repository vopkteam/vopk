#!/usr/bin/env bash
# apkg - unified package manager frontend (hardened)
# Supports: apt/apt-get, pacman(+yay/AUR), dnf, yum, zypper, apk (Alpine),
#           xbps (Void), emerge (Gentoo)
# NOTE: This script is intentionally conservative for safety.
# LINUX ONLY. USE AT YOUR OWN RISK.
# LICENSE: MIT
set -euo pipefail

APKG_VERSION="0.6.0"

# ------------- logging helpers -------------

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

log()  { printf "${BOLD}[APKG]${RESET} ${GREEN}[INF]${RESET} %s\n" "$*" >&2; }
warn() { printf "${BOLD}[APKG]${RESET} ${YELLOW}[WARN]${RESET} %s\n" "$*" >&2; }
die()  { printf "${BOLD}[APKG]${RESET} ${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

# لطيف مع Ctrl+C / kill
trap 'echo; die "Operation interrupted by user."' INT TERM

# ------------- global flags -------------

APKG_ASSUME_YES=0
APKG_ARGS=()

parse_global_flags() {
  APKG_ARGS=()
  for arg in "$@"; do
    case "$arg" in
      -y|--yes)
        APKG_ASSUME_YES=1
        ;;
      *)
        APKG_ARGS+=("$arg")
        ;;
    esac
  done
}

# ------------- sudo handling -------------

SUDO=""

init_sudo() {
  if [[ "${APKG_SUDO-}" != "" ]]; then
    if [[ "${APKG_SUDO}" == "" ]]; then
      SUDO=""
    else
      if command -v "${APKG_SUDO}" >/dev/null 2>&1; then
        SUDO="${APKG_SUDO}"
      else
        warn "APKG_SUDO='${APKG_SUDO}' not found in PATH."
        if [[ ${EUID} -eq 0 ]]; then
          warn "Running as root – continuing without sudo."
          SUDO=""
        else
          if command -v sudo >/dev/null 2>&1; then
            warn "Falling back to 'sudo'."
            SUDO="sudo"
          elif command -v doas >/dev/null 2>&1; then
            warn "Falling back to 'doas'."
            SUDO="doas"
          else
            die "No working privilege escalation tool (sudo/doas) found and not running as root."
          fi
        fi
      fi
    fi
  else
    if [[ ${EUID} -eq 0 ]]; then
      SUDO=""
    else
      if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
      elif command -v doas >/dev/null 2>&1; then
        warn "'sudo' not found, using 'doas' instead."
        SUDO="doas"
      else
        warn "Neither sudo nor doas found, and not running as root."
        warn "Commands requiring root may fail. Consider installing sudo or doas."
        SUDO=""
      fi
    fi
  fi
}

# ------------- package manager detection -------------

PKG_MGR=""
PKG_MGR_FAMILY=""   # debian, arch, redhat, suse, alpine, void, gentoo

detect_pkg_mgr() {
  # Arch detection with safety
  if [[ -f /etc/arch-release ]]; then
    if command -v pacman >/dev/null 2>&1; then
      PKG_MGR="pacman"
      PKG_MGR_FAMILY="arch"
      return
    else
      warn "Arch-based system detected (/etc/arch-release present) but 'pacman' is not in PATH."
      warn "This usually means the system is severely broken or is a minimal container image."
      if apkg_confirm "pacman not found, attempt to continue WITHOUT package manager?"; then
        die "Cannot safely install pacman automatically. Please repair/install pacman manually, then rerun apkg."
      else
        die "Cannot manage packages on Arch without pacman."
      fi
    fi
  fi

  # Normal detection order
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_MGR_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt-get"
    PKG_MGR_FAMILY="debian"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PKG_MGR_FAMILY="redhat"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    PKG_MGR_FAMILY="redhat"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
    PKG_MGR_FAMILY="suse"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_MGR_FAMILY="alpine"
  elif command -v xbps-install >/dev/null 2>&1; then
    PKG_MGR="xbps-install"
    PKG_MGR_FAMILY="void"
  elif command -v emerge >/dev/null 2>&1; then
    PKG_MGR="emerge"
    PKG_MGR_FAMILY="gentoo"
  # Debian-like minimal system without apt (dpkg only)
  elif [[ -f /etc/debian_version ]] && command -v dpkg >/dev/null 2>&1; then
    PKG_MGR="dpkg"
    PKG_MGR_FAMILY="debian_dpkg"
    warn "Debian-based system detected but no apt/apt-get found."
    warn "apkg will offer limited functionality using dpkg only (no repo installs)."
  else
    die "No supported package manager found (pacman/apt-get/dnf/yum/zypper/apk/xbps/emerge/dpkg)."
  fi
}

ensure_pkg_mgr() {
  if [[ -z "${PKG_MGR}" ]]; then
    detect_pkg_mgr
  fi
}

usage() {
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'

  printf "${BOLD}${BLUE}[APKG]${RESET} Unified Package Manager Frontend\n\n"

  printf "${BOLD}Usage:${RESET} ${GREEN}apkg [options] <command> [args]${RESET}\n\n"

  printf "${BOLD}Global options:${RESET}\n"
  printf "  ${YELLOW}-y, --yes${RESET}       Assume yes (or set ${YELLOW}APKG_ASSUME_YES=1${RESET})\n\n"

  printf "${BOLD}Core commands:${RESET}\n"
  printf "  ${GREEN}update${RESET}            Update package database\n"
  printf "  ${GREEN}upgrade${RESET}           Upgrade packages\n"
  printf "  ${GREEN}full-upgrade${RESET}      Full system upgrade\n"
  printf "  ${GREEN}install PKG...${RESET}    Install package(s)\n"
  printf "  ${GREEN}remove PKG...${RESET}     Remove package(s)\n"
  printf "  ${GREEN}purge PKG...${RESET}      Remove packages + configs\n"
  printf "  ${GREEN}autoremove${RESET}        Remove orphan dependencies\n"
  printf "  ${GREEN}search PATTERN${RESET}    Search packages\n"
  printf "  ${GREEN}list${RESET}              List installed packages\n"
  printf "  ${GREEN}show PKG${RESET}          Show package info\n"
  printf "  ${GREEN}clean${RESET}             Clean cache\n\n"

  printf "${BOLD}Repos:${RESET}\n"
  printf "  ${GREEN}repos-list${RESET}        List repos\n"
  printf "  ${GREEN}add-repo ARGS...${RESET}  Add repo\n"
  printf "  ${GREEN}remove-repo PAT${RESET}   Remove/disable repo\n\n"

  printf "${BOLD}System & Dev:${RESET}\n"
  printf "  ${GREEN}install-dev-kit${RESET}   Install dev tools\n"
  printf "  ${GREEN}fix-dns${RESET}           Fix DNS issues\n"
  printf "  ${GREEN}sys-info${RESET}          System info\n"
  printf "  ${GREEN}kernel${RESET}            Kernel version\n"
  printf "  ${GREEN}disk${RESET}              Disk usage\n"
  printf "  ${GREEN}mem${RESET}               Memory usage\n"
  printf "  ${GREEN}top${RESET}               htop/top\n"
  printf "  ${GREEN}ps${RESET}                Top processes\n"
  printf "  ${GREEN}ip${RESET}                Network info\n\n"

  printf "${BOLD}General:${RESET}\n"
  printf "  ${GREEN}-v | --version${RESET}    Show version\n"
  printf "  ${GREEN}help${RESET}              Show this help\n\n"

  printf "${BOLD}Env:${RESET}\n"
  printf "  ${YELLOW}APKG_SUDO=\"\"${RESET}        Disable sudo/doas\n"
  printf "  ${YELLOW}APKG_SUDO=\"doas\"${RESET}    Use doas\n"
  printf "  ${YELLOW}APKG_ASSUME_YES=1${RESET}   Assume yes\n"
}


# ------------- helpers -------------

print_pkg_not_found_msgs() {
  for p in "$@"; do
    printf 'apkg: The Package "%s" Not Found\n' "$p" >&2
  done
}

apkg_confirm() {
  local msg="$1"

  if [[ "${APKG_ASSUME_YES}" -eq 1 ]]; then
    echo "apkg: ${msg} [y/N]: y (auto)"
    return 0
  fi

  local ans
  read -r -p "apkg: ${msg} [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      echo "apkg: Operation cancelled."
      return 1
      ;;
  esac
}

run_and_capture() {
  local __var="$1"; shift
  local __tmp
  __tmp="$(mktemp /tmp/apkg-log.XXXXXX)"

  local __status=0

  set +e
  "$@" 2>&1 | tee "$__tmp"
  __status=$?
  set -e

  local __data=""
  if [[ -s "$__tmp" ]]; then
    __data="$(cat "$__tmp")"
  fi
  rm -f "$__tmp"

  printf -v "$__var" '%s' "$__data"
  return "$__status"
}

# -------- preview helper (non-fatal dry-run) --------
apkg_preview() {
  # usage: apkg_preview <cmd> <args...>
  # runs command in "ignore failure" mode (بعض مديري الحزم بيرجعوا non-zero في الـ dry-run)
  set +e
  "$@"
  local _st=$?
  set -e
  return 0
}

# ------------- package existence checks (generic) -------------

APKG_PRESENT_PKGS=()
APKG_MISSING_PKGS=()

redhat_pkg_exists() {
  ${PKG_MGR} info "$1" >/dev/null 2>&1
}

suse_pkg_exists() {
  zypper info "$1" >/dev/null 2>&1
}

alpine_pkg_exists() {
  apk info -e "$1" >/dev/null 2>&1
}

void_pkg_exists() {
  xbps-query -RS "$1" >/dev/null 2>&1
}

arch_pkg_exists() {
  pacman -Si "$1" >/dev/null 2>&1
}

check_pkgs_exist_generic() {
  local pkg
  APKG_PRESENT_PKGS=()
  APKG_MISSING_PKGS=()

  for pkg in "$@"; do
    case "${PKG_MGR_FAMILY}" in
      arch)
        if arch_pkg_exists "$pkg"; then
          APKG_PRESENT_PKGS+=("$pkg")
        else
          APKG_MISSING_PKGS+=("$pkg")
        fi
        ;;
      redhat)
        if redhat_pkg_exists "$pkg"; then
          APKG_PRESENT_PKGS+=("$pkg")
        else
          APKG_MISSING_PKGS+=("$pkg")
        fi
        ;;
      suse)
        if suse_pkg_exists "$pkg"; then
          APKG_PRESENT_PKGS+=("$pkg")
        else
          APKG_MISSING_PKGS+=("$pkg")
        fi
        ;;
      alpine)
        if alpine_pkg_exists "$pkg"; then
          APKG_PRESENT_PKGS+=("$pkg")
        else
          APKG_MISSING_PKGS+=("$pkg")
        fi
        ;;
      void)
        if void_pkg_exists "$pkg"; then
          APKG_PRESENT_PKGS+=("$pkg")
        else
          APKG_MISSING_PKGS+=("$pkg")
        fi
        ;;
      gentoo)
        # For safety/simplicity we don't aggressively guess missing packages here.
        APKG_PRESENT_PKGS+=("$pkg")
        ;;
      *)
        # Fallback: assume present (handled more specifically in debian functions)
        APKG_PRESENT_PKGS+=("$pkg")
        ;;
    esac
  done

  if ((${#APKG_MISSING_PKGS[@]} > 0)); then
    print_pkg_not_found_msgs "${APKG_MISSING_PKGS[@]}"
  fi
}

# ------------- Debian-specific helpers -------------

debian_fix_pkg_name() {
  local name="$1"
  case "$name" in
    docker)
      warn "On Debian/Ubuntu, 'docker' package is usually named 'docker.io'. Using 'docker.io'."
      echo "docker.io"
      ;;
    node)
      warn "On Debian/Ubuntu, 'node' is usually 'nodejs'. Using 'nodejs'."
      echo "nodejs"
      ;;
    pip|python-pip)
      warn "On Debian/Ubuntu, pip is typically 'python3-pip'. Using 'python3-pip'."
      echo "python3-pip"
      ;;
    *)
      echo "$name"
      ;;
  esac
}

debian_pkg_exists() {
  local pkg="$1"
  local out=""
  if ! out="$(apt-cache policy "$pkg" 2>/dev/null)"; then
    return 1
  fi
  if grep -q "Candidate: (none)" <<<"$out"; then
    return 1
  fi
  return 0
}

debian_install_pkgs() {
  local original_pkgs=("$@")
  local fixed_pkgs=()
  local present=()
  local missing=()

  local p fixed
  for p in "${original_pkgs[@]}"; do
    fixed="$(debian_fix_pkg_name "$p")"
    if [[ "$fixed" != "$p" ]]; then
      log "Mapped package '$p' -> '$fixed' for Debian/Ubuntu."
    fi
    fixed_pkgs+=("$fixed")
  done

  # إذا ما في apt/apt-get لكن في dpkg: نسمح فقط بملفات .deb محلية
  if [[ "${PKG_MGR_FAMILY}" == "debian_dpkg" || "${PKG_MGR}" == "dpkg" ]]; then
    local debs=()
    for p in "${fixed_pkgs[@]}"; do
      if [[ -f "$p" && "$p" == *.deb ]]; then
        debs+=("$p")
      else
        missing+=("$p")
      fi
    done

    if ((${#missing[@]} > 0)); then
      warn "On dpkg-only systems apkg can only install local .deb files."
      print_pkg_not_found_msgs "${missing[@]}"
    fi

    if ((${#debs[@]} == 0)); then
      warn "No .deb files to install with dpkg."
      return 1
    fi

    echo "apkg: Local .deb files to install:"
    printf '  %s\n' "${debs[@]}"

    echo
    log "dpkg dry-run (showing packages that would be installed from these .deb files)..."
    apkg_preview ${SUDO} dpkg -i --dry-run "${debs[@]}"
    echo

    if ! apkg_confirm "Install these .deb files via dpkg?"; then
      return 1
    fi

    ${SUDO} dpkg -i "${debs[@]}"
    return 0
  fi

  # apt موجود: نستخدمه بشكل عادي لكن بعد ما نتحقق من وجود البكجات
  for p in "${fixed_pkgs[@]}"; do
    if debian_pkg_exists "$p"; then
      present+=("$p")
    else
      missing+=("$p")
    fi
  done

  if ((${#missing[@]} > 0)); then
    print_pkg_not_found_msgs "${missing[@]}"
  fi

  if ((${#present[@]} == 0)); then
    warn "No valid packages to install."
    return 1
  fi

  echo "apkg: Packages to install (Debian/Ubuntu):"
  printf '  %s\n' "${present[@]}"

  echo
  log "APT dry-run (showing ALL packages that would be installed, including dependencies)..."
  apkg_preview ${SUDO} ${PKG_MGR} install --dry-run "${present[@]}"
  echo

  if ! apkg_confirm "Install packages: ${present[*]} ?"; then
    return 1
  fi

  local out=""
  if run_and_capture out ${SUDO} ${PKG_MGR} install -y "${present[@]}"; then
    return 0
  else
    if grep -qi 'Could not get lock /var/lib/dpkg/lock-frontend' <<<"$out"; then
      warn "apt/dpkg is currently locked by another process."
      warn "Another apt/apt-get or software updater is running."
      warn "Wait for it to finish or close it, then retry 'apkg install'."
      return 1
    fi

    if grep -qi 'Unable to locate package' <<<"$out"; then
      print_pkg_not_found_msgs "${present[@]}"
    else
      warn "Install failed."
    fi
    return 1
  fi
}

# ------------- Arch: pacman + yay (مع AUR) -------------

install_yay_if_needed() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  if [[ ${EUID} -eq 0 ]]; then
    warn "Running as root; refusing to bootstrap yay from AUR as root."
    warn "Use a normal user to install yay, then run apkg from that user."
    return 1
  fi

  log "Bootstrapping 'yay' from AUR..."

  if ! command -v git >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
    log "Installing 'base-devel' and 'git' via pacman before building yay..."
    if ! ${SUDO} pacman -S --needed --noconfirm base-devel git; then
      warn "Failed to install base-devel/git needed for building yay."
      return 1
    fi
  fi

  local tmpdir
  tmpdir="$(mktemp -d /tmp/apkg-yay-XXXXXX)"

  if ! git clone --depth=1 https://aur.archlinux.org/yay.git "$tmpdir" >/dev/null 2>&1; then
    warn "Failed to clone yay AUR repository."
    rm -rf "$tmpdir"
    return 1
  fi

  if ! (cd "$tmpdir" && makepkg -si --noconfirm); then
    warn "Failed to build/install yay via makepkg."
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  log "'yay' installed successfully."
  return 0
}

# Arch install logic:
# - يجرب pacman أولاً
# - أي باكدج مش في official يعتبر مرشح AUR
# - يحاول يثبت مرشحي AUR بـ yay
# - ما يقول "not found" إلا بعد ما يحاول AUR
arch_install_with_yay() {
  local pkgs=("$@")
  local official_pkgs=()
  local aur_candidates=()
  local p

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    die "You must specify at least one package to install."
  fi

  # صنّف البكجات: official vs AUR-candidate
  for p in "${pkgs[@]}"; do
    if pacman -Si "$p" >/dev/null 2>&1; then
      official_pkgs+=("$p")
    else
      aur_candidates+=("$p")
    fi
  done

  if ((${#official_pkgs[@]} == 0 && ${#aur_candidates[@]} == 0)); then
    warn "No valid packages to install (Arch)."
    return 1
  fi

  echo "apkg: Packages to install (Arch official repos):"
  if ((${#official_pkgs[@]} > 0)); then
    printf '  %s\n' "${official_pkgs[@]}"
  else
    echo "  (none)"
  fi

  echo "apkg: Packages to install (AUR candidates):"
  if ((${#aur_candidates[@]} > 0)); then
    printf '  %s\n' "${aur_candidates[@]}"
  else
    echo "  (none)"
  fi

  # ---- pacman dry-run preview ----
  if ((${#official_pkgs[@]} > 0)); then
    echo
    log "pacman dry-run (all packages that would be installed from official repos, including deps):"
    apkg_preview pacman -S --needed --print-format '%n' "${official_pkgs[@]}"
    echo
  fi

  if ((${#aur_candidates[@]} > 0)); then
    echo
    log "AUR note: yay will resolve and show AUR dependencies during installation."
  fi

  if ! apkg_confirm "Proceed with installation?"; then
    return 1
  fi

  # أولاً: pacman للأوفشال
  if ((${#official_pkgs[@]} > 0)); then
    local out_pac=""
    if ! run_and_capture out_pac ${SUDO} pacman -S --needed --noconfirm "${official_pkgs[@]}"; then
      warn "Error while installing via pacman. Check the log above."
    fi
  fi

  # ثانياً: AUR عبر yay
  if ((${#aur_candidates[@]} > 0)); then
    if ! install_yay_if_needed; then
      warn "Could not set up 'yay' for AUR installation."
      print_pkg_not_found_msgs "${aur_candidates[@]}"
      return 1
    fi

    local yay_out=""
    if ! run_and_capture yay_out yay -S --needed --noconfirm "${aur_candidates[@]}"; then
      if grep -qiE 'not found|could not find|no such package' <<< "$yay_out"; then
        print_pkg_not_found_msgs "${aur_candidates[@]}"
      else
        warn "Error while installing via yay. Check the log above."
      fi
      return 1
    fi
  fi

  return 0
}

# ------------- core package commands -------------

cmd_update() {
  ensure_pkg_mgr
  if ! apkg_confirm "Update package database now?"; then
    return 1
  fi

  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} update
      ;;
    debian_dpkg)
      warn "No apt found; cannot update repo metadata on dpkg-only systems."
      ;;
    arch)
      ${SUDO} pacman -Sy --noconfirm
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} makecache
      ;;
    suse)
      ${SUDO} zypper refresh
      ;;
    alpine)
      ${SUDO} apk --no-interactive update
      ;;
    void)
      ${SUDO} xbps-install -S
      ;;
    gentoo)
      ${SUDO} emerge --sync
      ;;
  esac
}

cmd_upgrade() {
  ensure_pkg_mgr
  if ! apkg_confirm "Upgrade installed packages now?"; then
    return 1
  fi

  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} upgrade -y
      ;;
    debian_dpkg)
      warn "dpkg-only mode: full upgrade via repos is not possible (no apt)."
      ;;
    arch)
      ${SUDO} pacman -Su --noconfirm
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} upgrade -y
      ;;
    suse)
      ${SUDO} zypper update -y
      ;;
    alpine)
      ${SUDO} apk --no-interactive upgrade
      ;;
    void)
      ${SUDO} xbps-install -Su
      ;;
    gentoo)
      ${SUDO} emerge -uD @world
      ;;
  esac
}

cmd_full_upgrade() {
  ensure_pkg_mgr
  if ! apkg_confirm "Perform a full system upgrade?"; then
    return 1
  fi

  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} dist-upgrade -y
      ;;
    debian_dpkg)
      warn "dpkg-only mode: full upgrade via repos is not possible (no apt)."
      ;;
    arch)
      ${SUDO} pacman -Syu --noconfirm
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} upgrade -y
      ;;
    suse)
      ${SUDO} zypper dist-upgrade -y || ${SUDO} zypper dup -y
      ;;
    alpine)
      ${SUDO} apk --no-interactive update
      ${SUDO} apk --no-interactive upgrade
      ;;
    void)
      ${SUDO} xbps-install -Su
      ;;
    gentoo)
      ${SUDO} emerge -uD @world
      ;;
  esac
}

cmd_install() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify at least one package to install."
  fi

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      debian_install_pkgs "$@"
      ;;

    arch)
      arch_install_with_yay "$@"
      ;;

    redhat)
      check_pkgs_exist_generic "$@"
      if ((${#APKG_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (RedHat family)."
        return 1
      fi
      echo "apkg: Packages to install (RedHat):"
      printf '  %s\n' "${APKG_PRESENT_PKGS[@]}"

      echo
      log "RedHat dry-run (showing ALL packages that would be installed, including dependencies)..."
      if [[ "${PKG_MGR}" == "dnf" ]]; then
        apkg_preview ${SUDO} dnf install --assumeno "${APKG_PRESENT_PKGS[@]}"
      else
        apkg_preview ${SUDO} ${PKG_MGR} install --assumeno "${APKG_PRESENT_PKGS[@]}"
      fi
      echo

      if ! apkg_confirm "Install packages: ${APKG_PRESENT_PKGS[*]} ?"; then
        return 1
      fi
      local out=""
      if run_and_capture out ${SUDO} ${PKG_MGR} install -y "${APKG_PRESENT_PKGS[@]}"; then
        return 0
      else
        if grep -qiE 'No match for argument|Unable to find a match' <<< "$out"; then
          print_pkg_not_found_msgs "${APKG_PRESENT_PKGS[@]}"
        else
          warn "Install failed."
        fi
        return 1
      fi
      ;;

    suse)
      check_pkgs_exist_generic "$@"
      if ((${#APKG_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (SUSE)."
        return 1
      fi
      echo "apkg: Packages to install (SUSE):"
      printf '  %s\n' "${APKG_PRESENT_PKGS[@]}"

      echo
      log "zypper dry-run (showing ALL packages that would be installed, including dependencies)..."
      apkg_preview ${SUDO} zypper install -y --dry-run "${APKG_PRESENT_PKGS[@]}"
      echo

      if ! apkg_confirm "Install packages: ${APKG_PRESENT_PKGS[*]} ?"; then
        return 1
      fi
      local out_s=""
      if run_and_capture out_s ${SUDO} zypper install -y "${APKG_PRESENT_PKGS[@]}"; then
        return 0
      else
        if grep -qi 'not found in package names' <<< "$out_s"; then
          print_pkg_not_found_msgs "${APKG_PRESENT_PKGS[@]}"
        else
          warn "Install failed."
        fi
        return 1
      fi
      ;;

    alpine)
      check_pkgs_exist_generic "$@"
      if ((${#APKG_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (Alpine)."
        return 1
      fi
      echo "apkg: Packages to install (Alpine):"
      printf '  %s\n' "${APKG_PRESENT_PKGS[@]}"

      echo
      log "apk dry-run (showing ALL packages that would be installed, including dependencies)..."
      apkg_preview ${SUDO} apk add --no-interactive --simulate "${APKG_PRESENT_PKGS[@]}"
      echo

      if ! apkg_confirm "Install packages: ${APKG_PRESENT_PKGS[*]} ?"; then
        return 1
      fi
      local out_a=""
      if run_and_capture out_a ${SUDO} apk add --no-interactive "${APKG_PRESENT_PKGS[@]}"; then
        return 0
      else
        if grep -qi 'not found' <<< "$out_a"; then
          print_pkg_not_found_msgs "${APKG_PRESENT_PKGS[@]}"
        else
          warn "Install failed."
        fi
        return 1
      fi
      ;;

    void)
      check_pkgs_exist_generic "$@"
      if ((${#APKG_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (Void)."
        return 1
      fi
      echo "apkg: Packages to install (Void):"
      printf '  %s\n' "${APKG_PRESENT_PKGS[@]}"

      echo
      log "xbps-install dry-run (showing ALL packages that would be installed, including dependencies)..."
      if command -v xbps-install >/dev/null 2>&1; then
        apkg_preview ${SUDO} xbps-install --dry-run "${APKG_PRESENT_PKGS[@]}"
      fi
      echo

      if ! apkg_confirm "Install packages: ${APKG_PRESENT_PKGS[*]} ?"; then
        return 1
      fi
      local out_v=""
      if run_and_capture out_v ${SUDO} xbps-install -y "${APKG_PRESENT_PKGS[@]}"; then
        return 0
      else
        if grep -qi 'not found in repository pool' <<< "$out_v"; then
          print_pkg_not_found_msgs "${APKG_PRESENT_PKGS[@]}"
        else
          warn "Install failed."
        fi
        return 1
      fi
      ;;

    gentoo)
      echo "apkg: Packages to install (Gentoo):"
      printf '  %s\n' "$@"

      echo
      log "emerge pretend (showing ALL packages that would be merged, including dependencies)..."
      apkg_preview ${SUDO} emerge -p "$@"
      echo

      if ! apkg_confirm "Install packages: $* ?"; then
        return 1
      fi
      local out_g=""
      if run_and_capture out_g ${SUDO} emerge "$@"; then
        return 0
      else
        if grep -qi 'emerge: there are no ebuilds to satisfy' <<< "$out_g"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Install failed."
        fi
        return 1
      fi
      ;;
  esac
}

cmd_remove() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify at least one package to remove."
  fi
  echo "apkg: Packages to remove:"
  printf '  %s\n' "$@"
  if ! apkg_confirm "Remove packages: $* ?"; then
    return 1
  fi

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      ${SUDO} ${PKG_MGR:-apt-get} remove -y "$@" || ${SUDO} dpkg -r "$@"
      ;;
    arch)
      ${SUDO} pacman -R --noconfirm "$@"
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} remove -y "$@"
      ;;
    suse)
      ${SUDO} zypper remove -y "$@"
      ;;
    alpine)
      ${SUDO} apk del --no-interactive "$@"
      ;;
    void)
      if command -v xbps-remove >/dev/null 2>&1; then
        ${SUDO} xbps-remove -y "$@"
      else
        die "xbps-remove not found."
      fi
      ;;
    gentoo)
      ${SUDO} emerge -C "$@"
      ;;
  esac
}

cmd_purge() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify at least one package to purge."
  fi
  echo "apkg: Packages to purge:"
  printf '  %s\n' "$@"
  if ! apkg_confirm "Purge packages (remove with configs): $* ?"; then
    return 1
  fi

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
        ${SUDO} ${PKG_MGR:-apt-get} purge -y "$@"
      else
        ${SUDO} dpkg -P "$@"
      fi
      ;;
    arch)
      ${SUDO} pacman -Rns --noconfirm "$@"
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} remove -y "$@"
      ;;
    suse)
      ${SUDO} zypper remove -y "$@"
      ;;
    alpine)
      ${SUDO} apk del --no-interactive "$@"
      ;;
    void)
      if command -v xbps-remove >/dev/null 2>&1; then
        ${SUDO} xbps-remove -y "$@"
      else
        die "xbps-remove not found."
      fi
      ;;
    gentoo)
      ${SUDO} emerge -C "$@"
      ;;
  esac
}

cmd_autoremove() {
  ensure_pkg_mgr
  if ! apkg_confirm "Autoremove unused/orphan packages?"; then
    return 1
  fi

  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} autoremove -y
      ;;
    debian_dpkg)
      warn "Autoremove not supported in dpkg-only mode."
      ;;
    arch)
      local ORPHANS
      ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
      if [[ -n "${ORPHANS-}" ]]; then
        log "Removing orphaned packages:"
        printf '%s\n' "${ORPHANS}"
        ${SUDO} pacman -Rns --noconfirm ${ORPHANS}
      else
        log "No orphaned packages found."
      fi
      ;;
    redhat)
      if [[ "${PKG_MGR}" == "dnf" ]]; then
        ${SUDO} dnf autoremove -y
      else
        warn "Autoremove not explicitly supported for ${PKG_MGR}."
      fi
      ;;
    suse)
      warn "Autoremove not explicitly supported for zypper (manual cleanup required)."
      ;;
    alpine)
      warn "Autoremove not explicitly supported for apk."
      ;;
    void|gentoo)
      warn "Autoremove/orphan cleanup not implemented for ${PKG_MGR_FAMILY}."
      ;;
  esac
}

cmd_search() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must provide a search pattern."
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      apt-cache search "$@"
      ;;
    debian_dpkg)
      warn "Search via dpkg-only mode is limited."
      dpkg -l | grep -i "$1" || true
      ;;
    arch)
      pacman -Ss "$@"
      ;;
    redhat)
      ${PKG_MGR} search "$@"
      ;;
    suse)
      zypper search "$@"
      ;;
    alpine)
      apk search "$@"
      ;;
    void)
      xbps-query -Rs "$@"
      ;;
    gentoo)
      emerge -s "$@"
      ;;
  esac
}

cmd_list() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      dpkg -l
      ;;
    arch)
      pacman -Q
      ;;
    redhat)
      ${PKG_MGR} list installed || rpm -qa
      ;;
    suse)
      zypper search --installed-only
      ;;
    alpine)
      apk info
      ;;
    void)
      xbps-query -l
      ;;
    gentoo)
      if command -v qlist >/dev/null 2>&1; then
        qlist -I
      else
        warn "qlist not found, cannot list installed packages cleanly."
      fi
      ;;
  esac
}

cmd_show() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify a package name."
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      local out=""
      if run_and_capture out apt-cache show "$@"; then
        return 0
      else
        if grep -qi 'E: No packages found' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed."
        fi
        return 1
      fi
      ;;
    debian_dpkg)
      dpkg -l "$@" || print_pkg_not_found_msgs "$@"
      ;;
    arch)
      local out_a=""
      if run_and_capture out_a pacman -Si "$@"; then
        return 0
      else
        if grep -qi 'target not found' <<< "$out_a"; then
          if command -v yay >/dev/null 2>&1; then
            local out_aur=""
            if run_and_capture out_aur yay -Si "$@"; then
              return 0
            fi
          fi
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed."
        fi
        return 1
      fi
      ;;
    redhat)
      local out_r=""
      if run_and_capture out_r ${PKG_MGR} info "$@"; then
        return 0
      else
        if grep -qiE 'No matching Packages to list|Error: No matching Packages' <<< "$out_r"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed."
        fi
        return 1
      fi
      ;;
    suse)
      local out_s=""
      if run_and_capture out_s zypper info "$@"; then
        return 0
      else
        if grep -qi 'not found in package names' <<< "$out_s"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed."
        fi
        return 1
      fi
      ;;
    alpine)
      local out_al=""
      if run_and_capture out_al apk info -a "$@"; then
        return 0
      else
        if grep -qi 'not found' <<< "$out_al"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed."
        fi
        return 1
      fi
      ;;
    void)
      local out_v=""
      if run_and_capture out_v xbps-query -RS "$@"; then
        return 0
      else
        if grep -qi 'not found in repository pool' <<< "$out_v"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed."
        fi
        return 1
      fi
      ;;
    gentoo)
      if command -v equery >/dev/null 2>&1; then
        equery meta "$@"
      else
        warn "equery not found, show not fully implemented for Gentoo."
      fi
      ;;
  esac
}

cmd_clean() {
  ensure_pkg_mgr
  if ! apkg_confirm "Clean package cache?"; then
    return 1
  fi

  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} clean
      ;;
    debian_dpkg)
      warn "No apt cache to clean in dpkg-only mode."
      ;;
    arch)
      ${SUDO} pacman -Scc --noconfirm
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} clean all
      ;;
    suse)
      ${SUDO} zypper clean --all
      ;;
    alpine)
      warn "apk cache cleaning depends on your setup (e.g. /var/cache/apk)."
      ;;
    void)
      if command -v xbps-remove >/dev/null 2>&1; then
        ${SUDO} xbps-remove -O
      else
        warn "xbps-remove not found, cannot clean cache."
      fi
      ;;
    gentoo)
      warn "Clean not implemented for Gentoo (use eclean/distclean tools)."
      ;;
  esac
}

# ------------- repo management -------------

cmd_repos_list() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      echo "=== /etc/apt/sources.list ==="
      [[ -f /etc/apt/sources.list ]] && cat /etc/apt/sources.list || echo "Not found."
      echo
      echo "=== /etc/apt/sources.list.d/*.list ==="
      ls /etc/apt/sources.list.d/*.list 2>/dev/null || echo "No extra list files."
      ;;
    arch)
      echo "=== /etc/pacman.conf (repos sections) ==="
      if [[ -f /etc/pacman.conf ]]; then
        grep -E '^\[.+\]' /etc/pacman.conf || true
      else
        echo "pacman.conf not found."
      fi
      ;;
    redhat)
      echo "=== /etc/yum.repos.d/*.repo ==="
      ls /etc/yum.repos.d/*.repo 2>/dev/null || echo "No repo files found."
      ;;
    suse)
      echo "=== zypper repos ==="
      zypper lr
      ;;
    alpine)
      echo "=== /etc/apk/repositories ==="
      [[ -f /etc/apk/repositories ]] && cat /etc/apk/repositories || echo "Not found."
      ;;
    void)
      echo "=== /etc/xbps.d/*.conf ==="
      ls /etc/xbps.d/*.conf 2>/dev/null || echo "No repo config files."
      ;;
    gentoo)
      echo "Repos are defined in /etc/portage/repos.conf and /etc/portage/make.conf."
      ;;
  esac
}

cmd_add_repo() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "Usage: apkg add-repo <repo-spec-or-url>"
  fi
  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      if command -v add-apt-repository >/dev/null 2>&1; then
        ${SUDO} add-apt-repository "$@"
      else
        warn "add-apt-repository not found. You may need to install 'software-properties-common'."
        die "Automatic repo add not supported. Edit /etc/apt/sources.list or /etc/apt/sources.list.d manually."
      fi
      ;;
    arch)
      warn "Automatic repo management for pacman is not supported by apkg."
      warn "Edit /etc/pacman.conf manually and run 'apkg update'."
      ;;
    redhat)
      if command -v dnf >/dev/null 2>&1 && command -v dnf-config-manager >/dev/null 2>&1; then
        ${SUDO} dnf config-manager --add-repo "$1"
      elif command -v yum-config-manager >/dev/null 2>&1; then
        ${SUDO} yum-config-manager --add-repo "$1"
      else
        die "No config manager (dnf-config-manager/yum-config-manager) found. Add repo manually under /etc/yum.repos.d."
      fi
      ;;
    suse)
      if [[ $# -lt 2 ]]; then
        die "Usage (suse): apkg add-repo <url> <alias>"
      fi
      ${SUDO} zypper ar "$1" "$2"
      ;;
    alpine)
      if [[ $# -ne 1 ]]; then
        die "Usage (alpine): apkg add-repo <repo-url-line>"
      fi
      if [[ ! -f /etc/apk/repositories ]]; then
        die "/etc/apk/repositories not found."
      fi
      ${SUDO} sh -c "echo '$1' >> /etc/apk/repositories"
      log "Added repo line to /etc/apk/repositories. Run 'apkg update'."
      ;;
    void|gentoo)
      warn "Repo add not automated for ${PKG_MGR_FAMILY}. Please edit config files manually."
      ;;
  esac
}

cmd_remove_repo() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "Usage: apkg remove-repo <pattern>"
  fi
  local pattern="$1"

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      warn "Will comment out lines matching '${pattern}' in /etc/apt/sources.list*."
      for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" ]] || continue
        ${SUDO} sed -i.bak "/${pattern}/ s/^/# disabled by apkg: /" "$f" || true
      done
      log "Done. Check *.bak backups if needed. Run 'apkg update'."
      ;;
    arch)
      warn "Automatic repo removal on pacman.conf is not supported."
      warn "Edit /etc/pacman.conf manually."
      ;;
    redhat)
      warn "Automatic repo removal is not fully supported."
      warn "You can disable .repo files under /etc/yum.repos.d/ manually."
      ;;
    suse)
      warn "Use 'zypper rr <alias>' directly for precise control."
      ;;
    alpine)
      if [[ ! -f /etc/apk/repositories ]]; then
        die "/etc/apk/repositories not found."
      fi
      ${SUDO} sed -i.bak "/${pattern}/d" /etc/apk/repositories
      log "Removed lines matching '${pattern}' from /etc/apk/repositories (backup: .bak)."
      ;;
    void|gentoo)
      warn "Repo removal not automated for ${PKG_MGR_FAMILY}; please edit config files manually."
      ;;
  esac
}

# ------------- dev kit -------------

cmd_install_dev_kit() {
  ensure_pkg_mgr
  if ! apkg_confirm "Install development tools (compiler, git, etc.)?"; then
    return 1
  fi

  log "Installing basic development tools (best-effort for ${PKG_MGR_FAMILY})..."
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} update
      # هنا مش عامل dry-run عشان دي عملية "meta" كبيرة؛ لو حابب أقدر أضيفها برضه بنفس الأسلوب
      ${SUDO} ${PKG_MGR} install -y build-essential git curl wget pkg-config
      ;;
    debian_dpkg)
      warn "dpkg-only mode: cannot pull dev tools from repos (no apt)."
      ;;
    arch)
      arch_install_with_yay base-devel git curl wget pkgconf
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} groupinstall -y "Development Tools" || true
      ${SUDO} ${PKG_MGR} install -y git curl wget pkgconfig
      ;;
    suse)
      ${SUDO} zypper install -y -t pattern devel_basis || true
      ${SUDO} zypper install -y git curl wget pkg-config
      ;;
    alpine)
      ${SUDO} apk add --no-interactive build-base git curl wget pkgconf
      ;;
    void)
      ${SUDO} xbps-install -y base-devel git curl wget pkg-config || true
      ;;
    gentoo)
      log "On Gentoo, dev tools are usually already present; ensure system profile includes them."
      ;;
  esac
  log "Dev kit installation finished."
}

# ------------- DNS fixer -------------

cmd_fix_dns() {
  log "Attempting to fix DNS issues (best-effort)."

  if [[ -L /etc/resolv.conf ]]; then
    warn "/etc/resolv.conf is a symlink. This usually means systemd-resolved or similar is managing DNS."
    if command -v systemctl >/dev/null 2>&1; then
      warn "Trying to restart systemd-resolved / NetworkManager if present."
      ${SUDO} systemctl restart systemd-resolved 2>/dev/null || true
      ${SUDO} systemctl restart NetworkManager 2>/dev/null || true
    fi
    log "Done basic service restarts. If DNS still broken, check your network manager settings."
    return 0
  fi

  if [[ -f /etc/resolv.conf ]]; then
    local backup="/etc/resolv.conf.apkg-backup-$(date +%Y%m%d%H%M%S)"
    log "Backing up /etc/resolv.conf to ${backup}"
    ${SUDO} cp /etc/resolv.conf "${backup}"
  fi

  log "Writing new /etc/resolv.conf with public DNS servers..."
  ${SUDO} sh -c 'cat > /etc/resolv.conf' <<EOF
# Generated by apkg fix-dns on $(date)
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF

  log "New /etc/resolv.conf written. Try 'ping 1.1.1.1' then 'ping google.com' to verify connectivity."
}

# ------------- system helpers -------------

cmd_sys_info() {
  echo "=== System info ==="
  uname -a || true
  echo
  echo "=== CPU ==="
  grep -m1 'model name' /proc/cpuinfo 2>/dev/null || echo "CPU info unavailable"
  echo
  echo "=== Memory ==="
  free -h 2>/dev/null || echo "free not available"
  echo
  echo "=== Disk (/) ==="
  df -h / || df -h || true
}

cmd_kernel() {
  uname -a
}

cmd_disk() {
  df -h
}

cmd_mem() {
  free -h || echo "free not available"
}

cmd_top() {
  if command -v htop >/dev/null 2>&1; then
    htop
  else
    top
  fi
}

cmd_ps() {
  ps aux --sort=-%mem | head -n 15
}

cmd_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip addr
    echo
    ip route || true
  else
    echo "'ip' command not found. Install iproute2 or equivalent."
  fi
}

# ------------- main dispatch -------------

main() {
  case "${1-}" in
    -v|--version)
      echo "apkg ${APKG_VERSION}"
      exit 0
      ;;
  esac

  local cmd="${1:-}"
  shift || true

  parse_global_flags "$@"
  set -- "${APKG_ARGS[@]}"

  case "${cmd}" in
    update)         cmd_update "$@" ;;
    upgrade)        cmd_upgrade "$@" ;;
    full-upgrade)   cmd_full_upgrade "$@" ;;
    dist-upgrade)   cmd_full_upgrade "$@" ;;

    install)        cmd_install "$@" ;;
    remove)         cmd_remove "$@" ;;
    purge)          cmd_purge "$@" ;;
    autoremove)     cmd_autoremove "$@" ;;

    search)         cmd_search "$@" ;;
    list)           cmd_list "$@" ;;
    show)           cmd_show "$@" ;;
    clean)          cmd_clean "$@" ;;

    repos-list)     cmd_repos_list "$@" ;;
    add-repo)       cmd_add_repo "$@" ;;
    remove-repo)    cmd_remove_repo "$@" ;;

    install-dev-kit) cmd_install_dev_kit "$@" ;;
    fix-dns)        cmd_fix_dns "$@" ;;

    sys-info)       cmd_sys_info ;;
    kernel)         cmd_kernel ;;
    disk)           cmd_disk ;;
    mem)            cmd_mem ;;
    top)            cmd_top ;;
    ps)             cmd_ps ;;
    ip)             cmd_ip ;;

    ""|help|-h|--help)
      usage
      ;;
    *)
      die "Unknown command: ${cmd}"
      ;;
  esac
}

# ------------- script entry point -------------
init_sudo
main "$@"
