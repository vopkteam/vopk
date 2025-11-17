# APKG — GP Team Unified Package Manager

**APKG** is a cross-distribution, production-ready, unified package manager developed and maintained by the **GP Team**.  
It provides a consistent command interface for managing software packages across multiple Linux distributions.

APKG abstracts away differences between package managers such as **apt**, **pacman**, **dnf**, **yum**, **zypper**, and **apk**, allowing you to perform common operations using a single, universal CLI tool.

---
## ✨ Features

- ✔ Unified interface across Linux distributions  
- ✔ Supports: apt, apt-get, pacman, dnf, yum, zypper, apk  
- ✔ Auto-detects system package manager  
- ✔ Production-grade design (`set -euo pipefail`)  
- ✔ Safe defaults with distro-specific commands  
- ✔ Optional sudo override (supports doas, nopass environments, containers)  
- ✔ System information helpers (kernel, disk, mem, IP, processes, etc.)  
- ✔ Clean, small, dependency-free Bash script  
- ✔ Works in servers, WSL, containers, VMs, embedded systems

---

## 📦 Supported Distributions

| Package Manager | Distributions |
|-----------------|-----------------------------|
| **apt / apt-get** | Ubuntu, Debian, Mint, PopOS |
| **pacman** | Arch Linux, Manjaro, EndeavourOS |
| **dnf** | Fedora |
| **yum** | CentOS, RHEL (legacy) |
| **zypper** | openSUSE |
| **apk** | Alpine Linux |

If a supported package manager is present in the system, APKG will detect and use it automatically.

---

## 🚀 Installation
```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/gpteamofficial/apkg/main/installscript.sh)
```
