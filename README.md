# APKG — The GP Team Unified Package Manager

**APKG** is a cross-distribution, production-ready **unified package manager** built and maintained by the **GP Team**.  
It provides **one CLI** for all major Linux distributions — with identical commands, identical options, and predictable behavior everywhere.

Whether you're on Debian, Ubuntu, Arch, Fedora, openSUSE, Alpine, Void, Gentoo, or inside a container/WSL/VM — **APKG just works**.
## 🚀 Why APKG?

Traditional Linux package managers are tied to their distros:

- `apt` for Debian/Ubuntu  
- `pacman` for Arch  
- `dnf/yum` for Fedora/CentOS  
- `zypper` for openSUSE  
- `apk` for Alpine  
- `xbps` for Void  
- `emerge` for Gentoo  

**APKG solves this fragmentation** by providing a **unified, consistent CLI** on top of all of them.

Examples:

```bash
# Instead of:
sudo dnf update
sudo pacman -S neovim
sudo apt remove firefox

# You can use:
sudo apkg update
sudo apkg install neovim
sudo apkg remove firefox
```
Same syntax. Same behavior. Everywhere.
## ✨ Features

- ✔ **Unified CLI** across all major Linux distributions  
- ✔ Supports **apt / apt-get, pacman, dnf, yum, zypper, apk, xbps, emerge**  
- ✔ **Automatic backend detection**  
- ✔ **dpkg fallback mode** (works even if apt is missing)  
- ✔ **Fast & safe** (`set -euo pipefail`, conservative behavior)  
- ✔ Clean and lightweight (single Bash script, zero extra deps)  
- ✔ Safe defaults with distro-specific optimizations  
- ✔ Works seamlessly on:
  - servers  
  - desktops  
  - WSL  
  - containers  
  - VMs  
  - embedded systems  
- ✔ Includes useful system helpers (sys info, kernel, mem, disk, IP, processes)
- ## 📦 Supported Package Managers

| Backend           | Distributions                                      |
|------------------|-----------------------------------------------------|
| **apt / apt-get**| Ubuntu, Debian, Mint, PopOS, Kali, etc.            |
| **pacman**       | Arch, Manjaro, EndeavourOS, etc.                   |
| **dnf**          | Fedora                                              |
| **yum**          | CentOS, RHEL (legacy)                               |
| **zypper**       | openSUSE                                            |
| **apk**          | Alpine Linux                                        |
| **xbps**         | Void Linux                                          |
| **emerge**       | Gentoo                                              |
| **dpkg (fallback)** | Debian-based systems without apt/apt-get        |

APKG automatically detects and uses the correct backend.

## 🔥 Drop-in replacement for APT

APKG can operate **with or without apt**:

- If `apt` / `apt-get` exist → APKG uses them as the backend  
- If no `apt` is found on a Debian-based system but `dpkg` exists → APKG switches to **dpkg-only mode**  
- In dpkg-only mode, APKG supports installing local `.deb` files and basic package operations

Example:

```bash
# Standard usage (apt backend)
sudo apkg install htop

# On minimal Debian systems with no apt:
sudo apkg install ./custom-package.deb
# apkg will use dpkg directly for .deb files
```
This makes APKG a self-reliant package manager capable of functioning even on minimal Debian/Ubuntu systems.
## 🏗 Installation

### One-liner installer (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gpteamofficial/apkg/main/installscript.sh)
```
### Alternative installer (if process substitution is blocked)
```
curl -fsSL https://raw.githubusercontent.com/gpteamofficial/apkg/main/installscript.sh | sudo bash
```
## 🛠 Maintenance (Update / Repair / Reinstall / Delete)

Use the maintenance script:

```bash
curl -fsSL https://raw.githubusercontent.com/gpteamofficial/apkg/main/updatescript.sh | sudo bash
```
From this menu you can:

- Update APKG

- Repair installation

- Reinstall

- Delete APKG

- Delete APKG + backup

## 📚 Basic Usage

Core commands:

```bash
# Update package database
apkg update

# Upgrade packages
apkg upgrade

# Full system upgrade
apkg full-upgrade

# Install / remove / purge
apkg install <package> [...]
apkg remove <package> [...]
apkg purge  <package> [...]

# Autoremove unused/orphan packages
apkg autoremove

# Search & info
apkg search <pattern>
apkg list
apkg show <package>

# Clean package cache
apkg clean
```
## 📂 Repository Management

```bash
# List configured repositories
apkg repos-list

# Add a repository (implementation depends on backend)
apkg add-repo <args...>

# Remove / disable repository entries by pattern
apkg remove-repo <pattern>
```
Behavior varies per backend (apt, zypper, yum/dnf, apk, etc.) and is intentionally conservative for safety.
## 🧠 System & Dev Helpers

APKG also includes helper commands:

```bash
# System & diagnostics
apkg sys-info      # overall system info
apkg kernel        # kernel version
apkg disk          # disk usage
apkg mem           # memory usage
apkg top           # run htop/top
apkg ps            # top processes
apkg ip            # network info

# Development kit (compilers, git, curl, etc.)
apkg install-dev-kit

# Try to fix common DNS issues
apkg fix-dns
```
## 🌍 Global Options & Environment

Global flags:

- `-y, --yes` → assume "yes" to prompts

Environment variables:

- `APKG_SUDO=""` → disable sudo/doas (run commands as-is)  
- `APKG_SUDO="doas"` → force using `doas`  
- `APKG_ASSUME_YES=1` → assume "yes" for confirmations (non-interactive usage)

Example:

```bash
APKG_ASSUME_YES=1 apkg upgrade
APKG_SUDO="doas" apkg install neovim
```
## 💚 Credits

APKG is developed and maintained by **GP Team**.  
A project built to simplify Linux package management across all environments.

## ⭐ Support the Project

If you like APKG:

- ⭐ Star the repository  
- 🐛 Open issues / feature requests  
- 📣 Share it with your community / friends / coworkers

