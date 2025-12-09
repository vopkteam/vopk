# VOPK — The Unified Package Frontend (formerly APKG)

**VOPK** is the next-generation, cross‑distribution, **unified package frontend** built and maintained by the **GP Team**.  
It provides **one CLI** for all major Linux distributions — with identical commands, predictable behavior, and a cleaner UX.
<p align="center">
  <a href="https://github.com/gpteamofficial/vopk">
    <img src="https://img.shields.io/badge/platform-Linux-333333?logo=linux&logoColor=ffffff" alt="Platform: Linux">
  </a>
  <a href="https://github.com/gpteamofficial/vopk">
    <img src="https://img.shields.io/badge/shell-BASH-4EAA25?logo=gnu-bash&logoColor=ffffff" alt="Shell: Bash">
  </a>
  <a href="https://github.com/gpteamofficial/vopk/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-GPL3-blue.svg" alt="License: MIT">
  </a>
  <a href="https://github.com/gpteamofficial/vopk">
    <img src="https://img.shields.io/badge/type-Unified%20pkg%20manager-ff6f00" alt="Unified package manager">
  </a>
</p>

> 🆕 **1.0.0 – the biggest update in APKG history**  
> - Project renamed from **APKG → VOPK**  
> - First official **stable** release (out of beta)  
> - New UX/UI, smart aliases, and better beginner‑friendly output  
> - Cleaner dry‑run behavior (no pointless prompts)  
> - Optional **vmpkg backend** support  
> - Many bug fixes and safety improvements

Whether you're on Debian, Ubuntu, Arch, Fedora, openSUSE, Alpine, Void, Gentoo, or inside a container/WSL/VM — **VOPK just works**.

---

## 🚀 Why VOPK?

Traditional Linux package managers are tied to their distros:

- `apt` / `apt-get` for Debian/Ubuntu  
- `pacman` for Arch  
- `dnf` / `yum` for Fedora/RHEL/CentOS  
- `zypper` for openSUSE  
- `apk` for Alpine  
- `xbps` for Void  
- `emerge` for Gentoo  

**VOPK solves this fragmentation** by providing a **unified, consistent CLI** on top of all of them.

Examples:

```bash
# Instead of:
sudo dnf update
sudo pacman -S neovim
sudo apt remove firefox

# You can use:
sudo vopk update
sudo vopk install neovim
sudo vopk remove firefox
```

Same syntax. Same mental model. Across all supported distros.

---

## ✨ Highlights in 1.0.0

- ✅ **New name & branding**: `apkg` → **`vopk`**
- ✅ **First stable release** (1.0.0), no longer a beta tool
- ✅ **Unified CLI** across all major Linux distributions
- ✅ Supports **apt / apt-get, pacman, dnf, yum, zypper, apk, xbps, emerge**
- ✅ **Automatic backend detection**
- ✅ **dpkg fallback mode** (works even if apt is missing)
- ✅ Optional **vmpkg backend** when no system package manager exists
- ✅ **Beginner‑friendly UX**: clearer messages, safer defaults
- ✅ **Clean dry‑run mode**:
  - Shows what would happen
  - **No `y/n` prompts** while in `--dry-run`
- ✅ Short, ergonomic **aliases** for common operations
- ✅ **Raw backend passthrough** for scripting (`vopk script-v` / `vopk backend`)
- ✅ Safe, hardened Bash implementation (`set -euo pipefail`)
- ✅ Single Bash script, zero external dependencies (beyond your package manager)
- ✅ Useful helpers: sys info, dev‑kit installer, DNS fixer, etc.

VOPK is designed to be comfortable for beginners while still powerful enough for advanced users and scripts.

---

## 📦 Supported Package Managers

| Backend              | Distributions / Notes                                      |
|----------------------|------------------------------------------------------------|
| **apt / apt-get**    | Ubuntu, Debian, Mint, PopOS, Kali, etc.                   |
| **pacman**           | Arch, Manjaro, EndeavourOS, etc.                          |
| **dnf**              | Fedora                                                     |
| **yum**              | CentOS, RHEL (legacy)                                      |
| **zypper**           | openSUSE                                                  |
| **apk**              | Alpine Linux                                              |
| **xbps-install**     | Void Linux                                                |
| **emerge**           | Gentoo                                                    |
| **dpkg (fallback)**  | Debian-based systems without apt/apt-get                  |
| **vmpkg (optional)** | If `vmpkg` is installed and no system PM is available     |

VOPK automatically detects and uses the correct backend for your environment.

---

## 🔥 Drop‑in replacement for APT (and more)

VOPK can operate **with or without apt**:

- If `apt` / `apt-get` exist → VOPK uses them as the backend  
- If no `apt` is found on a Debian-based system but `dpkg` exists → VOPK switches to **dpkg‑only mode**  
- In dpkg‑only mode, VOPK supports installing local `.deb` files and basic package operations

Example:

```bash
# Standard usage (apt backend)
sudo vopk install htop

# On minimal Debian systems with no apt:
sudo vopk install ./custom-package.deb
# vopk will use dpkg directly for .deb files
```

This makes VOPK a self‑reliant package interface capable of functioning even on minimal Debian/Ubuntu systems and containers.

---

## 🤝 vmpkg Integration (Optional Backend)

If you have **[vmpkg](https://github.com/gpteamofficial/vmpkg)** installed, VOPK can act as a friendly frontend for it too:

- If no system package manager is detected but `vmpkg` is available → VOPK uses **vmpkg** as backend
- You can also call vmpkg explicitly:

```bash
# Direct passthrough to vmpkg via vopk
vopk vm install my-package
vopk vmpkg list
```

Environment flags such as `VMPKG_ASSUME_YES`, `VMPKG_DRY_RUN`, etc., are automatically bridged when VOPK is using the vmpkg backend.

> Note: VOPK does **not** replace vmpkg’s logic; it simply offers a nicer entry point and unified feel when you move between systems.  

---

## 🏗 Installation

> ℹ️ Paths below assume the project is hosted under `gpteamofficial/vopk`.  
> Adjust the URLs if you are using a fork or a different namespace.

### One‑liner installer (recommended) (Must Be Run As Root User)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/installscript.sh)
```

### Alternative installer (Do NOT Needs ROOT User)

```bash
curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/installscript.sh | sudo bash -s -- -y
```

---

## 🛠 Maintenance (Update / Repair / Reinstall / Delete)

Use the maintenance script:

```bash
curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/updatescript.sh | sudo bash
```

From this menu you can:

- Update VOPK  
- Repair installation  
- Reinstall VOPK  
- Delete VOPK  
- Delete VOPK + backup

---

## 📚 Basic Usage

Core commands:

```bash
# Update package database
vopk update

# Upgrade packages
vopk upgrade

# Full system upgrade
vopk full-upgrade

# Install / remove / purge
vopk install <package> [...]
vopk remove  <package> [...]
vopk purge   <package> [...]

# Autoremove unused/orphan packages
vopk autoremove

# Search & info
vopk search <pattern>
vopk list
vopk show <package>

# Clean package cache
vopk clean
```

### Short aliases

To make life easier (especially for beginners), VOPK provides a few intuitive aliases:

```bash
# Aliases
vopk i   <pkg>      # install
vopk rm  <pkg>      # remove
vopk up             # update + upgrade
vopk fu             # full-upgrade
vopk ls             # list
vopk s   <pattern>  # search
vopk si  <pkg>      # show info
```

These are 100% optional — the long forms always work.

### Raw backend mode (for advanced scripting)

If you need to talk to the real package manager directly, with zero safety wrappers:

```bash
# Run the underlying backend exactly as-is
vopk script-v <backend-args>
vopk backend  <backend-args>

# Examples (depending on distro)
vopk script-v install -y htop          # apt/apt-get/dnf/…
vopk script-v -Syu                     # pacman
```

This is useful for scripts and power users who want one entry point (`vopk`) but full backend control.

---

## 📂 Repository Management

```bash
# List configured repositories
vopk repos-list

# Add a repository (implementation depends on backend)
vopk add-repo <args...>

# Remove / disable repository entries by pattern
vopk remove-repo <pattern>
```

Behavior varies per backend (apt, zypper, yum/dnf, apk, etc.) and is intentionally **conservative** for safety.

---

## 🧠 System & Dev Helpers

VOPK also includes helper commands:

```bash
# System & diagnostics
vopk sys-info      # overall system info
vopk kernel        # kernel version
vopk disk          # disk usage
vopk mem           # memory usage
vopk top           # run htop/top
vopk ps            # top processes
vopk ip            # network info

# Development kit (compilers, git, curl, etc.)
vopk install-dev-kit

# Try to fix common DNS issues
vopk fix-dns

# Check your environment & backend
vopk doctor
```

`vopk doctor` is especially useful when debugging weird behavior on minimal systems, containers, or WSL.

---

## 🌍 Global Options & Environment

Global flags:

- `-y, --yes, --assume-yes` → assume "yes" to prompts  
- `-n, --dry-run` → show what would happen, **no changes and no prompts**  
- `--no-color` → disable colored output  
- `--debug` → extra debug logging  
- `-q, --quiet` → hide info logs (only warnings/errors)

Environment variables (VOPK‑native):

- `VOPK_SUDO=""` → disable sudo/doas (run commands as-is)  
- `VOPK_SUDO="doas"` → force using `doas`  
- `VOPK_ASSUME_YES=1` → assume "yes" for confirmations (non-interactive usage)  
- `VOPK_DRY_RUN=1` → global dry‑run  
- `VOPK_NO_COLOR=1` → disable colors  
- `VOPK_DEBUG=1` → debug logs  
- `VOPK_QUIET=1` → hide info logs  

Backward‑compatibility environment variables (from APKG era):

- `APKG_SUDO`, `APKG_ASSUME_YES`, `APKG_DRY_RUN`, `APKG_NO_COLOR`, `APKG_DEBUG`, `APKG_QUIET`  
  → still respected, mapped internally to the new VOPK variables.

Examples:

```bash
VOPK_ASSUME_YES=1 vopk upgrade
VOPK_SUDO="doas"  vopk install neovim

# Old style (still works, for compatibility)
APKG_ASSUME_YES=1 vopk upgrade
```

---

## 🧱 Design Goals

- **Unified**: one mental model, one CLI, regardless of distro  
- **Safe**: conservative defaults, explicit confirmations, no surprise destructive actions  
- **Fast**: minimal shell overhead, direct calls into native package managers  
- **Transparent**: never hides backend errors, makes it clear what’s happening  
- **Beginner friendly**: short aliases, meaningful messages, and helper commands

---

## 💚 Credits

VOPK is developed and maintained by **GP Team**.  
Originally launched as **APKG**, this 1.0.0 release is the first official stable version under the **VOPK** name.

A project built to simplify Linux package management across all environments.

---

## ⭐ Support the Project

If you like VOPK:

- ⭐ Star the repository  
- 🐛 Open issues / feature requests  
- 📣 Share it with your community / friends / coworkers  
- 🔁 Package it for your favorite distro / template images

Happy Packages :) 🐧
