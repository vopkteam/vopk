<div align="center">

# 📦 VOPK
### The Ultimate Package Manager Wrapper
**One Command. Any Distro. Infinite Possibilities.**

[![Version](https://img.shields.io/badge/version-3.0.0_Jammy-blueviolet?style=flat-square)](https://github.com/vopkteam/vopk/releases)
[![License](https://img.shields.io/badge/license-GPLv3-green?style=flat-square)](LICENSE)
[![Bash](https://img.shields.io/badge/language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-pink?style=flat-square)](CONTRIBUTING.md)

[Installation](#-installation) • [Features](#-features) • [Documentation](https://vopkteam.github.io/vopk) • [Plugins](plugin/docs.md)

</div>

---

## 🚀 Introduction

**VOPK** (The Virtual One Package Kit) is a unified frontend that standardizes how you interact with software, regardless of the underlying operating system.

It does not replace `apt`, `pacman`, or `dnf`. Instead, it provides a **clean, intelligent, and predictable CLI** that auto-detects your environment and translates your intent into the correct native commands.

Whether you are managing a fleet of heterogeneous servers, hopping between Arch and Fedora, or orchestrating containers, VOPK ensures your muscle memory never needs to switch context.

**New in v3.0.0 "Jammy":** AI-powered suggestions, system benchmarking, plugin architecture, and transactional rollbacks.

---

## ⚡ Why VOPK?

The Linux ecosystem is fragmented. Installing a package looks different everywhere:

* **Debian:** `apt install -y pkg`
* **Arch:** `pacman -S --noconfirm pkg`
* **Fedora:** `dnf install -y pkg`
* **Alpine:** `apk add pkg`
* **macOS:** `brew install pkg`

**With VOPK, it is always:**

```bash
vopk install neovim
```

### The VOPK Advantage
* **Zero Dependencies:** A single, portable Bash script.
* **Context Aware:** Knows the difference between a system package, a flatpak, or an npm module.
* **Safe by Design:** Includes dry-runs, snapshots, and rollbacks.
* **Developer Ready:** Built-in benchmarking, auditing, and development environment setup.

---

## ✨ Key Features

### 🛡️ Universal Compatibility
Supports **50+ package managers** across **20+ distributions**.
* **System:** `apt`, `pacman`, `dnf`, `zypper`, `apk`, `xbps`, `emerge`, `nix`...
* **Language:** `npm`, `pip`, `cargo`, `go`, `gem`, `composer`, `maven`...
* **Universal:** `flatpak`, `snap`, `appimage`, `homebrew`.
* **Cloud & Container:** `docker`, `kubectl`, `helm`, `aws-cli`.

### 🧠 AI-Powered Intelligence
VOPK 3.0 doesn't just run commands; it assists you.
* **Smart Suggestions:** "Installing `docker`? You might also need `docker-compose`."
* **Conflict Detection:** Warns you before you break your system.
* **Auto-Fix:** The `vopk doctor` command uses heuristics to analyze and repair broken dependencies, DNS issues, and permissions.

### 🎨 Beautiful & Customizable
* **Theming:** Built-in themes (Dracula, Nord, Solarized, Monokai).
* **Animations:** Smooth, modern CLI experience with progress bars and spinners.
* **Rich Output:** Clear, color-coded logging (Success, Info, Warning, Error).

### 🔌 Extensible Plugin System
Need more power? Drop a script into `~/.config/vopk/plugins`.
* Create custom subcommands.
* Hook into the install/remove lifecycle.
* Access VOPK's core API for UI and logging.

---

## 📥 Installation

### Quick Start (Recommended)
Installs the latest stable version (3.0.0) to your system.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vopkteam/vopk/main/install.sh)
```

### Manual Installation
```bash
git clone https://github.com/vopkteam/vopk.git ~/.vopkbuild
cd ~/.vopkbuild/bin
sudo install -m 775 vopk /usr/local/bin/vopk
```

---

## 🛠️ Usage Guide

### Essentials
```bash
vopk update                # Update repo lists
vopk upgrade               # Upgrade all packages
vopk install <package>     # Smart install (checks repos, snaps, flatpaks)
vopk remove <package>      # Remove package
vopk clean --all           # Deep clean cache and temp files
```

### Advanced Operations (v3.0)
```bash
vopk doctor                # diagnose and fix system health
vopk benchmark             # Run CPU, Disk, and Network benchmarks
vopk snapshot              # Create a system restore point
vopk rollback              # Revert to previous state
vopk optimize              # Optimize DBs, trim SSDs, clear caches
```

### Configuration
VOPK supports `YAML`, `JSON`, `TOML`, and `.conf`.
Edit your preferences in `~/.config/vopk/config.yaml`:

```yaml
core:
  theme: "dracula"
  animations: true
  ai_suggestions: true
  security_scan: true
```

---

## 📊 Supported Backends Overview

| Category | Supported Tools |
| :--- | :--- |
| **Linux Distros** | Debian, Ubuntu, Arch, Fedora, CentOS, OpenSUSE, Alpine, Void, Gentoo, NixOS |
| **Unix-like** | macOS (Homebrew), FreeBSD, OpenBSD, NetBSD |
| **Universal** | Flatpak, Snap, AppImage, Homebrew (Linux) |
| **Languages** | Python (pip/poetry), Node (npm/yarn/pnpm), Rust (cargo), Go, PHP (composer), Java (mvn/gradle) |
| **DevOps** | Docker, Podman, AWS, Azure, Google Cloud, Kubernetes (k8s/helm), Terraform |
| **Gaming** | Steam, Lutris, Wine, Proton |

---

## 🤝 Community & Contributing

VOPK is built by the community, for the community. We believe in tools that respect the user's intelligence while automating the drudgery.

1.  **Star the repo** ⭐️ to show support!
2.  **Report Issues:** Found a bug? Open an issue on GitHub.
3.  **Submit PRs:** We love contributions! Check out `CONTRIBUTING.md`.

### License
VOPK is open-source software licensed under the **GPL-3.0 License**.

---

<div align="center">

**Happy Packaging! 📦**
<br>
<i>Crafted with ❤️ by the VOPK Team</i>

</div>