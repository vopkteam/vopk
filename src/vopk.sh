#!/usr/bin/env bash
# vopk - Unified Package Manager Frontend (1.1.0)
# Formerly: apkg
#
# Supports: apt/apt-get, pacman(+yay/AUR), dnf, yum, zypper, apk (Alpine),
#           xbps (Void), emerge (Gentoo), and optionally vmpkg.
#
# LICENSE: GPL 3

set -euo pipefail

VOPK_VERSION="1.1.0"

###############################################################################
# ENV / COMPAT
###############################################################################

: "${VOPK_ASSUME_YES:=${APKG_ASSUME_YES:-0}}"
: "${VOPK_DRY_RUN:=${APKG_DRY_RUN:-0}}"
: "${VOPK_NO_COLOR:=${APKG_NO_COLOR:-0}}"
: "${VOPK_DEBUG:=${APKG_DEBUG:-0}}"
: "${VOPK_QUIET:=${APKG_QUIET:-0}}"
: "${VOPK_SUDO:=${APKG_SUDO:-}}"

VOPK_ARGS=()

# Distro detection
DISTRO_ID=""
DISTRO_ID_LIKE=""
DISTRO_PRETTY_NAME=""

###############################################################################
# COLORS & UI
###############################################################################

BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
CYAN=$'\033[0;36m'
RESET=$'\033[0m'

apply_color_mode() {
  if [[ "$VOPK_NO_COLOR" -eq 1 || -n "${NO_COLOR-}" ]]; then
    BOLD=''; DIM=''; GREEN=''; YELLOW=''; RED=''; BLUE=''; MAGENTA=''; CYAN=''; RESET=''
  fi
}

timestamp() {
  date +"%H:%M:%S"
}

log() {
  if [[ "$VOPK_QUIET" -eq 1 ]]; then return; fi
  printf "%s[%s]%s %sVOPK%s %s✓%s %s\n" \
    "$DIM" "$(timestamp)" "$RESET" \
    "$BOLD$CYAN" "$RESET" \
    "$GREEN" "$RESET" \
    "$*" >&2
}

log_success() {
  if [[ "$VOPK_QUIET" -eq 1 ]]; then return; fi
  printf "%s[%s]%s %sVOPK%s %s✔ SUCCESS%s %s\n" \
    "$DIM" "$(timestamp)" "$RESET" \
    "$BOLD$CYAN" "$RESET" \
    "$GREEN" "$RESET" \
    "$*" >&2
}

warn() {
  printf "%s[%s]%s %sVOPK%s %s⚠ WARN%s %s\n" \
    "$DIM" "$(timestamp)" "$RESET" \
    "$BOLD$CYAN" "$RESET" \
    "$YELLOW" "$RESET" \
    "$*" >&2
}

die() {
  printf "%s[%s]%s %sVOPK%s %s✗ ERROR%s %s\n" \
    "$DIM" "$(timestamp)" "$RESET" \
    "$BOLD$CYAN" "$RESET" \
    "$RED" "$RESET" \
    "$*" >&2
  exit 1
}

debug() {
  if [[ "$VOPK_DEBUG" -eq 1 ]]; then
    printf "%s[%s]%s %sVOPK%s %sDBG%s %s\n" \
      "$DIM" "$(timestamp)" "$RESET" \
      "$BOLD$CYAN" "$RESET" \
      "$MAGENTA" "$RESET" \
      "$*" >&2
  fi
}

ui_hr() {
  printf "%s%s%s\n" "$DIM" "────────────────────────────────────────────────────────────" "$RESET"
}

ui_title() {
  local msg="$1"
  ui_hr
  printf "%s▶ %s%s\n" "$BOLD$BLUE" "$msg" "$RESET"
  ui_hr
}

ui_banner() {
  apply_color_mode
  printf "%s" "$BOLD$MAGENTA"
  cat <<'EOF'
 __     __  ____   ____  _  __
 \ \   / / |  _ \ / ___|| |/ /
  \ \ / /  | |_) |\___ \| ' / 
   \ V /   |  __/  ___) | . \ 
    \_/    |_|    |____/|_|\_\  Unified Package Frontend
EOF
  printf "%s\n" "$RESET"
  printf "%sVersion %s%s\n" "$DIM" "$VOPK_VERSION" "$RESET"
  ui_hr
}

###############################################################################
# SIGNAL HANDLING
###############################################################################

trap 'echo; die "Operation interrupted by user."' INT TERM

###############################################################################
# GLOBAL FLAGS
###############################################################################

parse_global_flags() {
  VOPK_ARGS=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      -y|--yes|--assume-yes) VOPK_ASSUME_YES=1 ;;
      -n|--dry-run)          VOPK_DRY_RUN=1 ;;
      --no-color)            VOPK_NO_COLOR=1 ;;
      --debug)               VOPK_DEBUG=1 ;;
      -q|--quiet)            VOPK_QUIET=1 ;;
      *)                     VOPK_ARGS+=("$arg") ;;
    esac
  done
}

vopk_confirm() {
  local msg="$1"
  if [[ "$VOPK_ASSUME_YES" -eq 1 ]]; then
    printf "vopk: %s [y/N]: y (auto)\n" "$msg"
    return 0
  fi

  local ans trimmed
  read -r -p "vopk: ${msg} [y/N]: " ans || true
  trimmed="${ans//[[:space:]]/}"

  case "$trimmed" in
    y|Y|yes|YES) return 0 ;;
    *) echo "vopk: Operation cancelled."; return 1 ;;
  esac
}

###############################################################################
# SUDO HANDLING
###############################################################################

SUDO=""

init_sudo() {
  if [[ -n "${VOPK_SUDO-}" ]]; then
    if [[ "${VOPK_SUDO}" == "" ]]; then
      SUDO=""
    else
      if command -v "${VOPK_SUDO}" >/dev/null 2>&1; then
        SUDO="${VOPK_SUDO}"
      else
        warn "VOPK_SUDO='${VOPK_SUDO}' not found in PATH."
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
            die "No privilege escalation tool (sudo/doas) found and not running as root."
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

###############################################################################
# DISTRO DETECTION
###############################################################################

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
    DISTRO_PRETTY_NAME="${PRETTY_NAME:-${NAME:-}}"
  else
    DISTRO_ID=""
    DISTRO_ID_LIKE=""
    DISTRO_PRETTY_NAME=""
  fi

  debug "Distro ID: ${DISTRO_ID:-?}, ID_LIKE: ${DISTRO_ID_LIKE:-?}, PRETTY: ${DISTRO_PRETTY_NAME:-?}"
}

is_ubuntu_like() {
  [[ "${DISTRO_ID}" == "ubuntu" || "${DISTRO_ID_LIKE}" == *ubuntu* ]]
}

is_debian_like() {
  [[ "${DISTRO_ID}" == "debian" || "${DISTRO_ID_LIKE}" == *debian* ]]
}

###############################################################################
# PACKAGE MANAGER DETECTION
###############################################################################

PKG_MGR=""
PKG_MGR_FAMILY=""   # debian, arch, redhat, suse, alpine, void, gentoo, debian_dpkg, vmpkg

detect_pkg_mgr() {
  if [[ -f /etc/arch-release ]]; then
    if command -v pacman >/dev/null 2>&1; then
      PKG_MGR="pacman"
      PKG_MGR_FAMILY="arch"
      return
    else
      warn "Arch-based system detected but 'pacman' is not in PATH."
      if vopk_confirm "pacman not found, continue without system package manager?"; then
        :
      else
        die "Cannot manage packages on Arch without pacman."
      fi
    fi
  fi

  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_MGR_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      PKG_MGR="apt-get"
    else
      PKG_MGR="apt"
    fi
    PKG_MGR_FAMILY="debian"  # will re-specialize behavior via DISTRO_ID
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
  elif command -v vmpkg >/dev/null 2>&1; then
    PKG_MGR="vmpkg"
    PKG_MGR_FAMILY="vmpkg"
    SUDO=""
    warn "No system package manager detected; vopk will use 'vmpkg' as backend."
  elif [[ -f /etc/debian_version ]] && command -v dpkg >/dev/null 2>&1; then
    PKG_MGR="dpkg"
    PKG_MGR_FAMILY="debian_dpkg"
    warn "Debian-based system detected but no apt/apt-get found."
    warn "vopk will offer limited functionality using dpkg only (no repo installs)."
  else
    die "No supported package manager found (pacman/apt/apt-get/dnf/yum/zypper/apk/xbps/emerge/dpkg/vmpkg)."
  fi

  debug "PKG_MGR=${PKG_MGR}, PKG_MGR_FAMILY=${PKG_MGR_FAMILY}"
}

ensure_pkg_mgr() {
  if [[ -z "${PKG_MGR}" ]]; then
    detect_pkg_mgr
  fi

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    export VMPKG_ASSUME_YES="${VOPK_ASSUME_YES}"
    export VMPKG_DRY_RUN="${VOPK_DRY_RUN}"
    export VMPKG_NO_COLOR="${VOPK_NO_COLOR}"
    export VMPKG_DEBUG="${VOPK_DEBUG}"
    export VMPKG_QUIET="${VOPK_QUIET}"
  fi
}

###############################################################################
# USAGE
###############################################################################

usage() {
  ui_banner

  printf "%sUsage:%s %svopk [options] <command> [args]%s\n\n" \
    "$BOLD" "$RESET" "$GREEN" "$RESET"

  printf "%sGlobal options:%s\n" "$BOLD" "$RESET"
  printf "  %s-y, --yes, --assume-yes%s    Assume yes for all prompts\n" "$YELLOW" "$RESET"
  printf "  %s-n, --dry-run%s             Preview only, no changes\n" "$YELLOW" "$RESET"
  printf "  %s--no-color%s                Disable colored output\n" "$YELLOW" "$RESET"
  printf "  %s--debug%s                   Verbose debug logging\n" "$YELLOW" "$RESET"
  printf "  %s-q, --quiet%s               Hide info logs\n\n" "$YELLOW" "$RESET"

  printf "%sCore commands:%s\n" "$BOLD" "$RESET"
  printf "  %supdate%s            Update package database\n" "$GREEN" "$RESET"
  printf "  %supgrade%s           Upgrade packages\n" "$GREEN" "$RESET"
  printf "  %sfull-upgrade%s      Full system upgrade\n" "$GREEN" "$RESET"
  printf "  %sinstall PKG...%s    Install package(s)\n" "$GREEN" "$RESET"
  printf "  %sremove PKG...%s     Remove package(s)\n" "$GREEN" "$RESET"
  printf "  %spurge PKG...%s      Remove packages + configs\n" "$GREEN" "$RESET"
  printf "  %sautoremove%s        Remove orphan dependencies\n" "$GREEN" "$RESET"
  printf "  %ssearch PATTERN%s    Search packages\n" "$GREEN" "$RESET"
  printf "  %slist%s              List installed packages\n" "$GREEN" "$RESET"
  printf "  %sshow PKG%s          Show package info\n" "$GREEN" "$RESET"
  printf "  %sclean%s             Clean cache\n\n" "$GREEN" "$RESET"

  printf "%sShort aliases:%s\n" "$BOLD" "$RESET"
  printf "  %si%s    = install\n" "$CYAN" "$RESET"
  printf "  %srm%s   = remove\n" "$CYAN" "$RESET"
  printf "  %sup%s   = update + upgrade\n" "$CYAN" "$RESET"
  printf "  %sfu%s   = full-upgrade\n" "$CYAN" "$RESET"
  printf "  %sls%s   = list\n" "$CYAN" "$RESET"
  printf "  %ss%s    = search\n" "$CYAN" "$RESET"
  printf "  %ssi%s   = show info\n\n" "$CYAN" "$RESET"

  printf "%sRepos:%s\n" "$BOLD" "$RESET"
  printf "  %srepos-list%s        List repos\n" "$GREEN" "$RESET"
  printf "  %sadd-repo ARGS...%s  Add repo\n" "$GREEN" "$RESET"
  printf "  %sremove-repo PAT%s   Remove/disable repo\n\n" "$GREEN" "$RESET"

  printf "%sSystem & Dev:%s\n" "$BOLD" "$RESET"
  printf "  %sinstall-dev-kit%s   Install dev tools\n" "$GREEN" "$RESET"
  printf "  %sfix-dns%s           Fix DNS issues\n" "$GREEN" "$RESET"
  printf "  %ssys-info%s          System info\n" "$GREEN" "$RESET"
  printf "  %sdoctor%s            Environment check\n" "$GREEN" "$RESET"
  printf "  %skernel%s            Kernel version\n" "$GREEN" "$RESET"
  printf "  %sdisk%s              Disk usage\n" "$GREEN" "$RESET"
  printf "  %smem%s               Memory usage\n" "$GREEN" "$RESET"
  printf "  %stop%s               htop/top\n" "$GREEN" "$RESET"
  printf "  %sps%s                Top processes\n" "$GREEN" "$RESET"
  printf "  %sip%s                Network info\n\n" "$GREEN" "$RESET"

  printf "%sBackends & raw:%s\n" "$BOLD" "$RESET"
  printf "  %sscript-v ...%s      Raw backend (apt-get/pacman/...) for scripts\n" "$GREEN" "$RESET"
  printf "  %sbackend ...%s       Alias for script-v\n" "$GREEN" "$RESET"
  printf "  %svm ...%s            Call vmpkg directly (if installed)\n" "$GREEN" "$RESET"
  printf "  %svmpkg ...%s         Same as 'vm'\n\n" "$GREEN" "$RESET"

  printf "%sEnvironment:%s\n" "$BOLD" "$RESET"
  printf "  %sVOPK_SUDO=\"\"%s           Disable sudo/doas\n" "$YELLOW" "$RESET"
  printf "  %sVOPK_SUDO=\"doas\"%s       Use doas\n" "$YELLOW" "$RESET"
  printf "  %sVOPK_ASSUME_YES=1%s       Assume yes\n" "$YELLOW" "$RESET"
  printf "  %sVOPK_DRY_RUN=1%s          Global dry-run\n" "$YELLOW" "$RESET"
  printf "  %sVOPK_NO_COLOR=1%s        Disable colors\n" "$YELLOW" "$RESET"
  printf "  %sVOPK_DEBUG=1%s           Enable debug logs\n" "$YELLOW" "$RESET"
  printf "  %sVOPK_QUIET=1%s           Hide info logs\n" "$YELLOW" "$RESET"
}

###############################################################################
# GENERIC HELPERS
###############################################################################

run_and_capture() {
  local __var="$1"; shift
  local __tmp
  __tmp="$(mktemp /tmp/vopk-log.XXXXXX)"

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

vopk_preview() {
  set +e
  "$@"
  local _st=$?
  set -e
  debug "preview exit status: ${_st}"
  return 0
}

print_pkg_not_found_msgs() {
  for p in "$@"; do
    printf 'vopk: The package "%s" was not found\n' "$p" >&2
  done
}

###############################################################################
# GENERIC PACKAGE EXISTENCE CHECKS
###############################################################################

VOPK_PRESENT_PKGS=()
VOPK_MISSING_PKGS=()

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
  VOPK_PRESENT_PKGS=()
  VOPK_MISSING_PKGS=()

  for pkg in "$@"; do
    case "${PKG_MGR_FAMILY}" in
      arch)
        if arch_pkg_exists "$pkg"; then
          VOPK_PRESENT_PKGS+=("$pkg")
        else
          VOPK_MISSING_PKGS+=("$pkg")
        fi
        ;;
      redhat)
        if redhat_pkg_exists "$pkg"; then
          VOPK_PRESENT_PKGS+=("$pkg")
        else
          VOPK_MISSING_PKGS+=("$pkg")
        fi
        ;;
      suse)
        if suse_pkg_exists "$pkg"; then
          VOPK_PRESENT_PKGS+=("$pkg")
        else
          VOPK_MISSING_PKGS+=("$pkg")
        fi
        ;;
      alpine)
        if alpine_pkg_exists "$pkg"; then
          VOPK_PRESENT_PKGS+=("$pkg")
        else
          VOPK_MISSING_PKGS+=("$pkg")
        fi
        ;;
      void)
        if void_pkg_exists "$pkg"; then
          VOPK_PRESENT_PKGS+=("$pkg")
        else
          VOPK_MISSING_PKGS+=("$pkg")
        fi
        ;;
      gentoo)
        VOPK_PRESENT_PKGS+=("$pkg")
        ;;
      *)
        VOPK_PRESENT_PKGS+=("$pkg")
        ;;
    esac
  done

  if ((${#VOPK_MISSING_PKGS[@]} > 0)); then
    print_pkg_not_found_msgs "${VOPK_MISSING_PKGS[@]}"
  fi
}

###############################################################################
# NAME MAPPERS (PER FAMILY)
###############################################################################

# Debian "pure" mapping
debian_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    # BASIC COMMON CONFUSIONS
    docker)
      mapped="docker.io"
      warn "On Debian, 'docker' is actually 'docker.io' in main repos."
      ;;
    node)
      mapped="nodejs"
      warn "'node' is 'nodejs' on Debian."
      ;;
    npm)
      mapped="npm"
      ;;
    pip|pip3|python-pip)
      mapped="python3-pip"
      warn "Using 'python3-pip' instead of 'pip'."
      ;;
    python)
      mapped="python3"
      warn "'python' command is 'python3' on modern Debian."
      ;;
    python2|python2-pip|pip2)
      warn "Python2 is deprecated and removed on modern Debian."
      mapped="python3"
      ;;
    # DEVELOPMENT TOOLS
    gcc|g++)
      mapped="build-essential"
      warn "'$name' is part of build-essential on Debian."
      ;;
    make)
      mapped="make"
      ;;
    cmake)
      mapped="cmake"
      ;;
    clang)
      mapped="clang"
      ;;
    # JS / WEB
    yarn)
      mapped="yarnpkg"
      warn "'yarn' package is named 'yarnpkg' on Debian."
      ;;
    typescript)
      mapped="node-typescript"
      warn "Using 'node-typescript' for Debian."
      ;;
    eslint)
      mapped="node-eslint"
      warn "eslint is provided as 'node-eslint' in Debian."
      ;;
    # DATABASES
    mysql)
      mapped="mariadb-server"
      warn "'mysql' is provided via 'mariadb-server' in Debian."
      ;;
    mysql-client)
      mapped="mariadb-client"
      warn "'mysql-client' is provided via 'mariadb-client' in Debian."
      ;;
    postgres|postgresql)
      mapped="postgresql"
      ;;
    mongodb)
      warn "MongoDB is NOT in official Debian repos. Using 'mongodb-clients' placeholder."
      mapped="mongodb-clients"
      ;;
    redis)
      mapped="redis-server"
      ;;
    # PHP
    php)
      mapped="php"
      ;;
    composer)
      mapped="composer"
      ;;
    # RUBY
    ruby-gems|rubygems)
      mapped="ruby-full"
      warn "Ruby gems are part of ruby-full."
      ;;
    # GO / RUST
    go|golang)
      mapped="golang-go"
      ;;
    rust)
      mapped="rustc"
      warn "Install 'rustc' (and possibly 'cargo'), or consider rustup."
      ;;
    cargo)
      mapped="cargo"
      ;;
    # SYSTEM UTILITIES
    ifconfig)
      mapped="net-tools"
      warn "'ifconfig' is provided by 'net-tools'."
      ;;
    iptables)
      mapped="iptables"
      ;;
    htop)
      mapped="htop"
      ;;
    neofetch)
      mapped="neofetch"
      ;;
    fastfetch)
      mapped="fastfetch"
      ;;
    tree)
      mapped="tree"
      ;;
    # LIBRARIES
    openssl)
      mapped="openssl"
      ;;
    ssl|libssl)
      mapped="libssl-dev"
      warn "'$name' mapped to 'libssl-dev'."
      ;;
    zlib)
      mapped="zlib1g"
      ;;
    zlib-dev|zlib-devel)
      mapped="zlib1g-dev"
      warn "'$name' mapped to 'zlib1g-dev'."
      ;;
    curl)
      mapped="curl"
      ;;
    wget)
      mapped="wget"
      ;;
    pkgconfig|pkg-config)
      mapped="pkg-config"
      ;;
    # JAVA
    java|jdk|openjdk)
      mapped="default-jdk"
      warn "Using 'default-jdk' on Debian."
      ;;
    # DEFAULT
    *)
      mapped="$name"
      ;;
  esac

  echo "$mapped"
}

# Ubuntu / Ubuntu-like mapping
ubuntu_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    docker)
      mapped="docker.io"
      warn "On Ubuntu, 'docker' is usually 'docker.io' from the official archive."
      ;;
    node)
      mapped="nodejs"
      warn "'node' is 'nodejs' in Ubuntu repos."
      ;;
    npm)
      mapped="npm"
      ;;
    pip|pip3|python-pip)
      mapped="python3-pip"
      warn "Using 'python3-pip' instead of 'pip'."
      ;;
    python)
      mapped="python3"
      warn "'python' command is 'python3' on modern Ubuntu."
      ;;
    mysql)
      mapped="mysql-server"
      warn "'mysql' maps to 'mysql-server' on Ubuntu."
      ;;
    mysql-client)
      mapped="mysql-client"
      ;;
    mongodb)
      warn "MongoDB is not in main Ubuntu repos (newer releases). Consider upstream instructions."
      mapped="mongodb-clients"
      ;;
    redis)
      mapped="redis-server"
      ;;
    yarnpkg)
      mapped="yarn"
      ;;
    yarn)
      mapped="yarn"
      ;;
    gcc|g++)
      mapped="build-essential"
      warn "'$name' is part of build-essential on Ubuntu."
      ;;
    go|golang)
      mapped="golang-go"
      ;;
    pkgconfig|pkg-config)
      mapped="pkg-config"
      ;;
    ifconfig)
      mapped="net-tools"
      warn "'ifconfig' is provided by 'net-tools'."
      ;;
    # Fallbacks similar to Debian
    *)
      mapped="$(debian_fix_pkg_name "$name")"
      ;;
  esac

  echo "$mapped"
}

# Arch mapping (pacman)
arch_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    node)
      mapped="nodejs"
      ;;
    pip|pip3|python-pip)
      mapped="python-pip"
      ;;
    python)
      mapped="python"
      ;;
    mysql)
      mapped="mariadb"
      ;;
    mysql-client)
      mapped="mariadb-clients"
      ;;
    redis)
      mapped="redis"
      ;;
    yarnpkg)
      mapped="yarn"
      ;;
    pkg-config)
      mapped="pkgconf"
      ;;
    ifconfig)
      mapped="net-tools"
      ;;
    build-essential)
      mapped="base-devel"
      ;;
    *)
      mapped="$name"
      ;;
  esac

  echo "$mapped"
}

# RedHat (dnf/yum) mapping
redhat_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    node)
      mapped="nodejs"
      ;;
    npm)
      mapped="npm"
      ;;
    pip|pip3|python-pip)
      mapped="python3-pip"
      ;;
    python)
      mapped="python3"
      ;;
    mysql)
      mapped="mariadb-server"
      warn "'mysql' is provided by 'mariadb-server' on many RedHat-based systems."
      ;;
    mysql-client)
      mapped="mariadb"
      ;;
    yarnpkg)
      mapped="yarn"
      ;;
    pkg-config)
      mapped="pkgconfig"
      ;;
    ifconfig)
      mapped="net-tools"
      ;;
    build-essential|base-devel)
      mapped="gcc"
      ;;
    *)
      mapped="$name"
      ;;
  esac

  echo "$mapped"
}

# SUSE (zypper) mapping
suse_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    node)
      mapped="nodejs"
      ;;
    npm)
      mapped="npm10"   # conservative; user can adjust
      ;;
    pip|pip3|python-pip)
      mapped="python3-pip"
      ;;
    python)
      mapped="python3"
      ;;
    mysql)
      mapped="mariadb"
      ;;
    mysql-client)
      mapped="mariadb-client"
      ;;
    ifconfig)
      mapped="net-tools-deprecated"
      ;;
    build-essential|base-devel)
      mapped="gcc"
      ;;
    *)
      mapped="$name"
      ;;
  esac

  echo "$mapped"
}

# Alpine (apk) mapping
alpine_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    node)
      mapped="nodejs"
      ;;
    npm)
      mapped="npm"
      ;;
    pip|pip3|python-pip)
      mapped="py3-pip"
      ;;
    python)
      mapped="python3"
      ;;
    mysql)
      mapped="mariadb"
      ;;
    mysql-client)
      mapped="mariadb-client"
      ;;
    build-essential|base-devel)
      mapped="build-base"
      ;;
    ifconfig)
      mapped="net-tools"
      ;;
    pkg-config)
      mapped="pkgconf"
      ;;
    *)
      mapped="$name"
      ;;
  esac

  echo "$mapped"
}

# Void (xbps) mapping
void_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    node)
      mapped="nodejs"
      ;;
    pip|pip3|python-pip)
      mapped="python3-pip"
      ;;
    python)
      mapped="python3"
      ;;
    mysql)
      mapped="mariadb-server"
      ;;
    mysql-client)
      mapped="mariadb-client"
      ;;
    build-essential|base-devel)
      mapped="base-devel"
      ;;
    ifconfig)
      mapped="net-tools"
      ;;
    pkg-config)
      mapped="pkg-config"
      ;;
    *)
      mapped="$name"
      ;;
  esac

  echo "$mapped"
}

# Gentoo (emerge) mapping
gentoo_fix_pkg_name() {
  local name="$1"
  local mapped=""

  case "$name" in
    node)
      mapped="net-libs/nodejs"
      ;;
    npm)
      mapped="net-libs/nodejs"
      ;;
    pip|pip3|python-pip)
      mapped="dev-python/pip"
      ;;
    python)
      mapped="dev-lang/python"
      ;;
    mysql)
      mapped="dev-db/mariadb"
      ;;
    mysql-client)
      mapped="dev-db/mariadb-tools"
      ;;
    build-essential|base-devel)
      mapped="system"
      ;;
    *)
      mapped="$name"
      ;;
  esac

  echo "$mapped"
}

###############################################################################
# DEBIAN HELPERS
###############################################################################

debian_pkg_exists() {
  local pkg="$1"
  debug "Checking Debian/Ubuntu package existence via apt-cache show: ${pkg}"
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

debian_install_pkgs() {
  local original_pkgs=("$@")
  local fixed_pkgs=()
  local present=()
  local missing=()

  local fix_fn="debian_fix_pkg_name"
  if is_ubuntu_like; then
    fix_fn="ubuntu_fix_pkg_name"
  fi

  local p fixed
  for p in "${original_pkgs[@]}"; do
    fixed="$("$fix_fn" "$p")"
    if [[ "$fixed" != "$p" ]]; then
      log "Mapped package '$p' -> '$fixed' for $(is_ubuntu_like && echo Ubuntu || echo Debian)."
    fi
    fixed_pkgs+=("$fixed")
  done

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
      warn "On dpkg-only systems vopk can only install local .deb files."
      print_pkg_not_found_msgs "${missing[@]}"
    fi

    if ((${#debs[@]} == 0)); then
      warn "No .deb files to install with dpkg."
      return 1
    fi

    echo "vopk: Local .deb files to install:"
    printf '  %s\n' "${debs[@]}"

    echo
    vopk_preview ${SUDO} dpkg -i --dry-run "${debs[@]}"
    echo

    if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
      return 0
    fi

    if ! vopk_confirm "Install these .deb files via dpkg?"; then
      return 1
    fi

    ${SUDO} dpkg -i "${debs[@]}"
    return 0
  fi

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

  echo "vopk: Packages to install ($(is_ubuntu_like && echo Ubuntu || echo Debian)):"
  printf '  %s\n' "${present[@]}"

  echo
  vopk_preview ${SUDO} ${PKG_MGR} install --dry-run "${present[@]}"
  echo

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  if ! vopk_confirm "Install packages: ${present[*]} ?"; then
    return 1
  fi

  local out=""
  if run_and_capture out ${SUDO} ${PKG_MGR} install -y "${present[@]}"; then
    return 0
  else
    warn "Install failed. Check log above for details."
    return 1
  fi
}

###############################################################################
# ARCH: PACMAN + YAY / AUR
###############################################################################

install_yay_if_needed() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  if [[ ${EUID} -eq 0 ]]; then
    warn "Running as root; refusing to bootstrap yay from AUR as root."
    warn "Use a normal user to install yay, then run vopk from that user."
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
  tmpdir="$(mktemp -d /tmp/vopk-yay-XXXXXX)"

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
  log_success "'yay' installed successfully."
  return 0
}

arch_install_with_yay() {
  local raw_pkgs=("$@")
  local pkgs=()
  local official_pkgs=()
  local aur_candidates=()
  local p fixed

  if [[ ${#raw_pkgs[@]} -eq 0 ]]; then
    die "You must specify at least one package to install."
  fi

  for p in "${raw_pkgs[@]}"; do
    fixed="$(arch_fix_pkg_name "$p")"
    if [[ "$fixed" != "$p" ]]; then
      log "Mapped package '$p' -> '$fixed' for Arch."
    fi
    pkgs+=("$fixed")
  done

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

  echo "vopk: Packages to install (Arch official repos):"
  if ((${#official_pkgs[@]} > 0)); then
    printf '  %s\n' "${official_pkgs[@]}"
  else
    echo "  (none)"
  fi

  echo "vopk: Packages to install (AUR candidates):"
  if ((${#aur_candidates[@]} > 0)); then
    printf '  %s\n' "${aur_candidates[@]}"
  else
    echo "  (none)"
  fi

  if ((${#official_pkgs[@]} > 0)); then
    echo
    vopk_preview pacman -S --needed --print-format '%n' "${official_pkgs[@]}"
    echo
  fi

  if ((${#aur_candidates[@]} > 0)); then
    echo
    echo "vopk: AUR packages will be handled via yay (if available)."
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  if ! vopk_confirm "Proceed with installation?"; then
    return 1
  fi

  if ((${#official_pkgs[@]} > 0)); then
    local out_pac=""
    if ! run_and_capture out_pac ${SUDO} pacman -S --needed --noconfirm "${official_pkgs[@]}"; then
      warn "Error while installing via pacman. Check the log above."
    fi
  fi

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

###############################################################################
# CORE PACKAGE COMMANDS
###############################################################################

cmd_update() {
  ensure_pkg_mgr
  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Backend 'vmpkg' has no package database to update."
    return 0
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian)      vopk_preview ${SUDO} ${PKG_MGR} update 2>/dev/null || true ;;
      debian_dpkg) warn "dpkg-only: no repo metadata to update." ;;
      arch)        vopk_preview ${SUDO} pacman -Sy --noconfirm ;;
      redhat)      vopk_preview ${SUDO} ${PKG_MGR} makecache ;;
      suse)        vopk_preview ${SUDO} zypper refresh ;;
      alpine)      vopk_preview ${SUDO} apk --no-interactive update ;;
      void)        vopk_preview ${SUDO} xbps-install -S ;;
      gentoo)      vopk_preview ${SUDO} emerge --sync ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Update package database now?"; then
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
  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Backend 'vmpkg' does not manage system upgrades."
    return 0
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian)      vopk_preview ${SUDO} ${PKG_MGR} upgrade -y ;;
      debian_dpkg) warn "dpkg-only: upgrades via repos not possible." ;;
      arch)        vopk_preview ${SUDO} pacman -Su --noconfirm ;;
      redhat)      vopk_preview ${SUDO} ${PKG_MGR} upgrade -y ;;
      suse)        vopk_preview ${SUDO} zypper update -y ;;
      alpine)      vopk_preview ${SUDO} apk --no-interactive upgrade ;;
      void)        vopk_preview ${SUDO} xbps-install -Su ;;
      gentoo)      vopk_preview ${SUDO} emerge -uD @world ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Upgrade installed packages now?"; then
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
  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Backend 'vmpkg' does not support full system upgrade."
    return 0
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian)      vopk_preview ${SUDO} ${PKG_MGR} dist-upgrade -y ;;
      debian_dpkg) warn "dpkg-only: full upgrade not possible." ;;
      arch)        vopk_preview ${SUDO} pacman -Syu --noconfirm ;;
      redhat)      vopk_preview ${SUDO} ${PKG_MGR} upgrade -y ;;
      suse)
        vopk_preview ${SUDO} zypper dist-upgrade -y || vopk_preview ${SUDO} zypper dup -y
        ;;
      alpine)
        vopk_preview ${SUDO} apk --no-interactive update
        vopk_preview ${SUDO} apk --no-interactive upgrade
        ;;
      void)        vopk_preview ${SUDO} xbps-install -Su ;;
      gentoo)      vopk_preview ${SUDO} emerge -uD @world ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Perform a full system upgrade?"; then
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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    exec vmpkg install "$@"
  fi

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      debian_install_pkgs "$@"
      ;;

    arch)
      arch_install_with_yay "$@"
      ;;

    redhat)
      local mapped=() p fixed
      for p in "$@"; do
        fixed="$(redhat_fix_pkg_name "$p")"
        if [[ "$fixed" != "$p" ]]; then
          log "Mapped package '$p' -> '$fixed' for RedHat-family."
        fi
        mapped+=("$fixed")
      done

      check_pkgs_exist_generic "${mapped[@]}"
      if ((${#VOPK_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (RedHat family)."
        return 1
      fi
      echo "vopk: Packages to install (RedHat):"
      printf '  %s\n' "${VOPK_PRESENT_PKGS[@]}"

      echo
      if [[ "${PKG_MGR}" == "dnf" ]]; then
        vopk_preview ${SUDO} dnf install --assumeno "${VOPK_PRESENT_PKGS[@]}"
      else
        vopk_preview ${SUDO} ${PKG_MGR} install --assumeno "${VOPK_PRESENT_PKGS[@]}"
      fi
      echo

      if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
        return 0
      fi

      if ! vopk_confirm "Install packages: ${VOPK_PRESENT_PKGS[*]} ?"; then
        return 1
      fi

      local out=""
      if run_and_capture out ${SUDO} ${PKG_MGR} install -y "${VOPK_PRESENT_PKGS[@]}"; then
        return 0
      else
        warn "Install failed."
        return 1
      fi
      ;;

    suse)
      local mapped_s=() sp sfix
      for sp in "$@"; do
        sfix="$(suse_fix_pkg_name "$sp")"
        if [[ "$sfix" != "$sp" ]]; then
          log "Mapped package '$sp' -> '$sfix' for SUSE."
        fi
        mapped_s+=("$sfix")
      done

      check_pkgs_exist_generic "${mapped_s[@]}"
      if ((${#VOPK_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (SUSE)."
        return 1
      fi
      echo "vopk: Packages to install (SUSE):"
      printf '  %s\n' "${VOPK_PRESENT_PKGS[@]}"

      echo
      vopk_preview ${SUDO} zypper install -y --dry-run "${VOPK_PRESENT_PKGS[@]}"
      echo

      if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
        return 0
      fi

      if ! vopk_confirm "Install packages: ${VOPK_PRESENT_PKGS[*]} ?"; then
        return 1
      fi

      local out_s=""
      if run_and_capture out_s ${SUDO} zypper install -y "${VOPK_PRESENT_PKGS[@]}"; then
        return 0
      else
        warn "Install failed."
        return 1
      fi
      ;;

    alpine)
      local mapped_a=() ap afix
      for ap in "$@"; do
        afix="$(alpine_fix_pkg_name "$ap")"
        if [[ "$afix" != "$ap" ]]; then
          log "Mapped package '$ap' -> '$afix' for Alpine."
        fi
        mapped_a+=("$afix")
      done

      check_pkgs_exist_generic "${mapped_a[@]}"
      if ((${#VOPK_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (Alpine)."
        return 1
      fi
      echo "vopk: Packages to install (Alpine):"
      printf '  %s\n' "${VOPK_PRESENT_PKGS[@]}"

      echo
      vopk_preview ${SUDO} apk add --no-interactive --simulate "${VOPK_PRESENT_PKGS[@]}"
      echo

      if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
        return 0
      fi

      if ! vopk_confirm "Install packages: ${VOPK_PRESENT_PKGS[*]} ?"; then
        return 1
      fi

      local out_a=""
      if run_and_capture out_a ${SUDO} apk add --no-interactive "${VOPK_PRESENT_PKGS[@]}"; then
        return 0
      else
        warn "Install failed."
        return 1
      fi
      ;;

    void)
      local mapped_v=() vp vfix
      for vp in "$@"; do
        vfix="$(void_fix_pkg_name "$vp")"
        if [[ "$vfix" != "$vp" ]]; then
          log "Mapped package '$vp' -> '$vfix' for Void."
        fi
        mapped_v+=("$vfix")
      done

      check_pkgs_exist_generic "${mapped_v[@]}"
      if ((${#VOPK_PRESENT_PKGS[@]} == 0)); then
        warn "No valid packages to install (Void)."
        return 1
      fi
      echo "vopk: Packages to install (Void):"
      printf '  %s\n' "${VOPK_PRESENT_PKGS[@]}"

      echo
      if command -v xbps-install >/dev/null 2>&1; then
        vopk_preview ${SUDO} xbps-install --dry-run "${VOPK_PRESENT_PKGS[@]}"
      fi
      echo

      if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
        return 0
      fi

      if ! vopk_confirm "Install packages: ${VOPK_PRESENT_PKGS[*]} ?"; then
        return 1
      fi

      local out_v=""
      if run_and_capture out_v ${SUDO} xbps-install -y "${VOPK_PRESENT_PKGS[@]}"; then
        return 0
      else
        warn "Install failed."
        return 1
      fi
      ;;

    gentoo)
      local mapped_g=() gp gfix
      for gp in "$@"; do
        gfix="$(gentoo_fix_pkg_name "$gp")"
        if [[ "$gfix" != "$gp" ]]; then
          log "Mapped package '$gp' -> '$gfix' for Gentoo."
        fi
        mapped_g+=("$gfix")
      done

      echo "vopk: Packages to install (Gentoo):"
      printf '  %s\n' "${mapped_g[@]}"

      echo
      vopk_preview ${SUDO} emerge -p "${mapped_g[@]}"
      echo

      if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
        return 0
      fi

      if ! vopk_confirm "Install packages: ${mapped_g[*]} ?"; then
        return 1
      fi

      local out_g=""
      if run_and_capture out_g ${SUDO} emerge "${mapped_g[@]}"; then
        return 0
      else
        warn "Install failed."
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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
      vmpkg remove "$@" -n || true
      return 0
    fi
    exec vmpkg remove "$@"
  fi

  echo "vopk: Packages to remove:"
  printf '  %s\n' "$@"

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian|debian_dpkg)
        vopk_preview ${SUDO} ${PKG_MGR:-apt-get} remove -y "$@" ;;
      arch)
        vopk_preview ${SUDO} pacman -R --noconfirm "$@" ;;
      redhat)
        vopk_preview ${SUDO} ${PKG_MGR} remove -y "$@" ;;
      suse)
        vopk_preview ${SUDO} zypper remove -y "$@" ;;
      alpine)
        vopk_preview ${SUDO} apk del --no-interactive "$@" ;;
      void)
        vopk_preview ${SUDO} xbps-remove -y "$@" ;;
      gentoo)
        vopk_preview ${SUDO} emerge -C "$@" ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Remove packages: $* ?"; then
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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Backend 'vmpkg' has no concept of purge; using remove."
    if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
      vmpkg remove "$@" -n || true
      return 0
    fi
    exec vmpkg remove "$@"
  fi

  echo "vopk: Packages to purge:"
  printf '  %s\n' "$@"

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian|debian_dpkg)
        vopk_preview ${SUDO} ${PKG_MGR:-apt-get} purge -y "$@" ;;
      arch)
        vopk_preview ${SUDO} pacman -Rns --noconfirm "$@" ;;
      redhat)
        vopk_preview ${SUDO} ${PKG_MGR} remove -y "$@" ;;
      suse)
        vopk_preview ${SUDO} zypper remove -y "$@" ;;
      alpine)
        vopk_preview ${SUDO} apk del --no-interactive "$@" ;;
      void)
        vopk_preview ${SUDO} xbps-remove -y "$@" ;;
      gentoo)
        vopk_preview ${SUDO} emerge -C "$@" ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Purge packages (remove with configs): $* ?"; then
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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Backend 'vmpkg' does not track system-level dependencies."
    return 0
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian) vopk_preview ${SUDO} ${PKG_MGR} autoremove -y ;;
      debian_dpkg)
        warn "Autoremove not supported in dpkg-only mode."
        ;;
      arch)
        local ORPHANS
        ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
        if [[ -n "${ORPHANS-}" ]]; then
          vopk_preview ${SUDO} pacman -Rns --noconfirm ${ORPHANS}
        fi
        ;;
      redhat)
        if [[ "${PKG_MGR}" == "dnf" ]]; then
          vopk_preview ${SUDO} dnf autoremove -y
        fi
        ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Autoremove unused/orphan packages?"; then
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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    exec vmpkg search "$@"
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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    exec vmpkg list
  fi

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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    exec vmpkg show "$@"
  fi

  case "${PKG_MGR_FAMILY}" in
    debian)
      local out=""
      if run_and_capture out apt-cache show "$@"; then
        return 0
      else
        warn "Show failed."
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

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
      vmpkg clean -n || true
      return 0
    fi
    exec vmpkg clean
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian)      vopk_preview ${SUDO} ${PKG_MGR} clean ;;
      debian_dpkg) warn "No apt cache to clean in dpkg-only mode." ;;
      arch)        vopk_preview ${SUDO} pacman -Scc --noconfirm ;;
      redhat)      vopk_preview ${SUDO} ${PKG_MGR} clean all ;;
      suse)        vopk_preview ${SUDO} zypper clean --all ;;
      alpine)      warn "apk cache cleaning depends on your setup (e.g. /var/cache/apk)." ;;
      void)
        if command -v xbps-remove >/dev/null 2>&1; then
          vopk_preview ${SUDO} xbps-remove -O
        fi
        ;;
      gentoo)      warn "Clean not implemented for Gentoo (use eclean/distclean tools)." ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Clean package cache?"; then
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

###############################################################################
# REPO MANAGEMENT
###############################################################################

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
    vmpkg)
      warn "vmpkg doesn't have system repos. It uses its own registry."
      ;;
  esac
}

cmd_add_repo() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "Usage: vopk add-repo <repo-spec-or-url>"
  fi

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Repo add is not applicable when using vmpkg backend."
    return 0
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      if command -v add-apt-repository >/dev/null 2>&1; then
        ${SUDO} add-apt-repository "$@"
      else
        warn "add-apt-repository not found. You may need 'software-properties-common'."
        die "Automatic repo add not supported. Edit /etc/apt/sources.list or /etc/apt/sources.list.d manually."
      fi
      ;;
    arch)
      warn "Automatic repo management for pacman is not supported by vopk."
      warn "Edit /etc/pacman.conf manually and run 'vopk update'."
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
        die "Usage (suse): vopk add-repo <url> <alias>"
      fi
      ${SUDO} zypper ar "$1" "$2"
      ;;
    alpine)
      if [[ $# -ne 1 ]]; then
        die "Usage (alpine): vopk add-repo <repo-url-line>"
      fi
      if [[ ! -f /etc/apk/repositories ]]; then
        die "/etc/apk/repositories not found."
      fi
      ${SUDO} sh -c "echo '$1' >> /etc/apk/repositories"
      log_success "Added repo line to /etc/apk/repositories. Run 'vopk update'."
      ;;
    void|gentoo)
      warn "Repo add not automated for ${PKG_MGR_FAMILY}. Please edit config files manually."
      ;;
  esac
}

cmd_remove_repo() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "Usage: vopk remove-repo <pattern>"
  fi
  local pattern="$1"

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Repo removal is not applicable when using vmpkg backend."
    return 0
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      warn "Will comment out lines matching '${pattern}' in /etc/apt/sources.list*."
      for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" ]] || continue
        ${SUDO} sed -i.bak "/${pattern}/ s/^/# disabled by vopk: /" "$f" || true
      done
      log_success "Done. Check *.bak backups if needed. Run 'vopk update'."
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
      log_success "Removed lines matching '${pattern}' from /etc/apk/repositories (backup: .bak)."
      ;;
    void|gentoo)
      warn "Repo removal not automated for ${PKG_MGR_FAMILY}; please edit config files manually."
      ;;
  esac
}

###############################################################################
# DEV KIT
###############################################################################

cmd_install_dev_kit() {
  ensure_pkg_mgr

  if [[ "${PKG_MGR_FAMILY}" == "vmpkg" ]]; then
    warn "Dev kit installation requires a system package manager, not vmpkg."
    return 0
  fi

  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    case "${PKG_MGR_FAMILY}" in
      debian)
        vopk_preview ${SUDO} ${PKG_MGR} update
        vopk_preview ${SUDO} ${PKG_MGR} install -y build-essential git curl wget pkg-config
        ;;
      debian_dpkg)
        warn "dpkg-only mode: cannot pull dev tools from repos (no apt)."
        ;;
      arch)
        vopk_preview arch_install_with_yay base-devel git curl wget pkgconf
        ;;
      redhat)
        vopk_preview ${SUDO} ${PKG_MGR} groupinstall -y "Development Tools"
        vopk_preview ${SUDO} ${PKG_MGR} install -y git curl wget pkgconfig
        ;;
      suse)
        vopk_preview ${SUDO} zypper install -y -t pattern devel_basis
        vopk_preview ${SUDO} zypper install -y git curl wget pkg-config
        ;;
      alpine)
        vopk_preview ${SUDO} apk add --no-interactive build-base git curl wget pkgconf
        ;;
      void)
        vopk_preview ${SUDO} xbps-install -y base-devel git curl wget pkg-config
        ;;
      gentoo)
        vopk_preview ${SUDO} emerge --info >/dev/null 2>&1 || true
        ;;
    esac
    return 0
  fi

  if ! vopk_confirm "Install development tools (compiler, git, etc.)?"; then
    return 1
  fi

  log "Installing basic development tools (best-effort for ${PKG_MGR_FAMILY})..."
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} update
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
  log_success "Dev kit installation finished."
}

###############################################################################
# DNS FIXER
###############################################################################

cmd_fix_dns() {
  if [[ "${VOPK_DRY_RUN}" -eq 1 ]]; then
    if [[ -L /etc/resolv.conf ]]; then
      vopk_preview ${SUDO} systemctl restart systemd-resolved 2>/dev/null || true
      vopk_preview ${SUDO} systemctl restart NetworkManager 2>/dev/null || true
    else
      :
    fi
    return 0
  fi

  log "Attempting to fix DNS issues (best-effort)."

  if [[ -L /etc/resolv.conf ]]; then
    warn "/etc/resolv.conf is a symlink (likely systemd-resolved or similar)."
    if command -v systemctl >/dev/null 2>&1; then
      warn "Trying to restart systemd-resolved / NetworkManager if present."
      ${SUDO} systemctl restart systemd-resolved 2>/dev/null || true
      ${SUDO} systemctl restart NetworkManager 2>/dev/null || true
    fi
    log_success "Basic DNS services restart done. If DNS still broken, check your network manager settings."
    return 0
  fi

  if [[ -f /etc/resolv.conf ]]; then
    local backup="/etc/resolv.conf.vopk-backup-$(date +%Y%m%d%H%M%S)"
    log "Backing up /etc/resolv.conf to ${backup}"
    ${SUDO} cp /etc/resolv.conf "${backup}"
  fi

  log "Writing new /etc/resolv.conf with public DNS servers..."
  ${SUDO} sh -c 'cat > /etc/resolv.conf' <<EOF
# Generated by vopk fix-dns on $(date)
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF

  log_success "New /etc/resolv.conf written. Try 'ping 1.1.1.1' then 'ping google.com' to verify connectivity."
}

###############################################################################
# SYSTEM HELPERS
###############################################################################

cmd_sys_info() {
  ui_title "System info"
  echo "=== uname -a ==="
  uname -a || true
  echo
  echo "=== OS (from /etc/os-release) ==="
  echo "ID:           ${DISTRO_ID:-?}"
  echo "ID_LIKE:      ${DISTRO_ID_LIKE:-?}"
  echo "PRETTY_NAME:  ${DISTRO_PRETTY_NAME:-?}"
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

cmd_doctor() {
  ui_title "vopk doctor"

  local uname_s
  uname_s="$(uname -s || echo "Unknown")"

  echo "Kernel:       $uname_s"
  echo "OS:           ${DISTRO_PRETTY_NAME:-Unknown}"
  echo "OS ID:        ${DISTRO_ID:-Unknown}"
  echo "OS ID_LIKE:   ${DISTRO_ID_LIKE:-Unknown}"
  echo "User:         $(id -un 2>/dev/null || echo '?')"
  echo "EUID:         ${EUID}"
  echo "SUDO cmd:     ${SUDO:-<none>}"
  ui_hr

  ensure_pkg_mgr
  echo "Backend:      ${PKG_MGR_FAMILY:-<none>} (${PKG_MGR:-<none>})"
  ui_hr

  echo "PATH:         $PATH"
  ui_hr

  case "${PKG_MGR_FAMILY}" in
    debian|debian_dpkg)
      if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
        log_success "APT backend detected."
      else
        warn "APT not detected; dpkg-only mode."
      fi
      ;;
    arch)
      if command -v pacman >/dev/null 2>&1; then
        log_success "pacman detected."
      else
        warn "pacman not in PATH."
      fi
      ;;
    redhat)
      if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        log_success "DNF/YUM backend detected."
      else
        warn "DNF/YUM not in PATH."
      fi
      ;;
    suse)
      if command -v zypper >/dev/null 2>&1; then
        log_success "zypper detected."
      else
        warn "zypper not in PATH."
      fi
      ;;
    alpine)
      if command -v apk >/dev/null 2>&1; then
        log_success "apk detected."
      else
        warn "apk not in PATH."
      fi
      ;;
    void)
      if command -v xbps-install >/dev/null 2>&1; then
        log_success "xbps-install detected."
      else
        warn "xbps-install not in PATH."
      fi
      ;;
    gentoo)
      if command -v emerge >/dev/null 2>&1; then
        log_success "emerge detected."
      else
        warn "emerge not in PATH."
      fi
      ;;
    vmpkg)
      if command -v vmpkg >/dev/null 2>&1; then
        log_success "vmpkg detected as backend."
      else
        warn "vmpkg backend selected but not found in PATH."
      fi
      ;;
  esac

  echo
  if command -v curl >/dev/null; then
    log_success "curl detected."
  elif command -v wget >/dev/null; then
    log_success "wget detected."
  else
    warn "Neither curl nor wget is installed. Some tools may not work."
  fi

  if command -v tar >/dev/null; then
    log_success "tar detected."
  else
    warn "tar not found."
  fi

  if command -v unzip >/dev/null; then
    log_success "unzip detected."
  else
    warn "unzip not found."
  fi
}

###############################################################################
# script-v / backend (RAW MODE)
###############################################################################

cmd_script_v() {
  ensure_pkg_mgr
  debug "script-v backend: ${PKG_MGR_FAMILY} / ${PKG_MGR}"

  case "${PKG_MGR_FAMILY}" in
    debian)
      exec ${SUDO} ${PKG_MGR} "$@"
      ;;
    debian_dpkg)
      exec ${SUDO} dpkg "$@"
      ;;
    arch)
      exec ${SUDO} pacman "$@"
      ;;
    redhat|suse|alpine|void|gentoo)
      exec ${SUDO} ${PKG_MGR} "$@"
      ;;
    vmpkg)
      exec vmpkg "$@"
      ;;
    *)
      die "script-v mode is not supported for this system."
      ;;
  esac
}

###############################################################################
# MAIN DISPATCH
###############################################################################

main() {
  case "${1-}" in
    -v|--version)
      echo "vopk ${VOPK_VERSION}"
      exit 0
      ;;
  esac

  local cmd="${1:-}"
  shift || true

  if [[ "${cmd}" == "vm" || "${cmd}" == "vmpkg" ]]; then
    if ! command -v vmpkg >/dev/null 2>&1; then
      die "vmpkg not found in PATH."
    fi
    exec vmpkg "$@"
  fi

  if [[ "${cmd}" == "script-v" || "${cmd}" == "backend" ]]; then
    cmd_script_v "$@"
    exit $?
  fi

  parse_global_flags "$@"
  set -- "${VOPK_ARGS[@]}"

  apply_color_mode

  case "${cmd}" in
    update)         cmd_update "$@" ;;
    upgrade|u)      cmd_upgrade "$@" ;;
    full-upgrade|dist-upgrade|fu) cmd_full_upgrade "$@" ;;

    install|i)      cmd_install "$@" ;;
    remove|rm)      cmd_remove "$@" ;;
    purge)          cmd_purge "$@" ;;
    autoremove)     cmd_autoremove "$@" ;;

    search|s)       cmd_search "$@" ;;
    list|ls)        cmd_list "$@" ;;
    show|si)        cmd_show "$@" ;;
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
    doctor)         cmd_doctor ;;

    up)             cmd_update; cmd_upgrade ;;

    ""|help|-h|--help)
      usage
      ;;
    *)
      die "Unknown command: ${cmd}"
      ;;
  esac
}

###############################################################################
# ENTRY POINT
###############################################################################

detect_distro
init_sudo
main "$@"
