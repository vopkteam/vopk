# 🤝 Contributing to VOPK

> **First off, thank you for considering contributing to VOPK!**
> It's people like you who make the open-source community such an amazing place to learn, inspire, and create.

VOPK is a community-driven project. We welcome contributions of all forms: bug reports, feature requests, documentation improvements, and code submissions.

---

## 📜 Table of Contents
1. [Code of Conduct](#-code-of-conduct)
2. [How Can I Contribute?](#-how-can-i-contribute)
   - [Reporting Bugs](#reporting-bugs)
   - [Suggesting Enhancements](#suggesting-enhancements)
   - [Your First Code Contribution](#your-first-code-contribution)
3. [Development Guide](#-development-guide)
   - [Environment Setup](#environment-setup)
   - [Running Tests](#running-tests)
   - [Bash Style Guide](#bash-style-guide)
4. [Submission Guidelines](#-submission-guidelines)

---

## ⚖️ Code of Conduct
This project adheres to a simple code of conduct: **Be respectful, be collaborative, and assume positive intent.** Harassment or abusive behavior will not be tolerated.

---

## 🚀 How Can I Contribute?

### Reporting Bugs
Bugs are tracked as [GitHub Issues](https://github.com/vopkteam/vopk/issues).
When filing an issue, please include:
1.  **Your OS:** (e.g., Ubuntu 22.04, Arch Linux, macOS Sonoma).
2.  **VOPK Version:** Run `vopk --version`.
3.  **Debug Output:** Run the command with `-d` (e.g., `vopk install firefox -d`) and paste the output.
4.  **System Health:** The output of `vopk doctor` is often helpful.

### Suggesting Enhancements
Have an idea for a killer feature?
* **Check existing issues** to see if it's already planned.
* **Open a Feature Request** describing *what* you want to achieve and *why*.
* If it's a specific tool integration, consider writing it as a **Plugin** first! (See `plugin/docs.md`).

### Your First Code Contribution
Unsure where to begin? You can start by looking through these issues:
* **`good first issue`**: Issues which should only require a few lines of code.
* **`help wanted`**: Issues which may be a bit more involved.

---

## 🛠 Development Guide

### Environment Setup
VOPK is a standalone Bash script, but for development, we recommend a safe environment (VM or Container) to avoid accidentally messing up your host system's packages.

1.  **Fork and Clone:**
    ```bash
    git clone [https://github.com/YOUR-USERNAME/vopk.git](https://github.com/YOUR-USERNAME/vopk.git)
    cd vopk
    ```

2.  **Make it executable:**
    ```bash
    chmod +x vopk
    ```

3.  **Run in Dev Mode:**
    You can run the script directly from the source:
    ```bash
    ./vopk --version
    ```

### Running Tests
Since VOPK interacts with system package managers, we rely heavily on **Dry Runs** and **ShellCheck**.

1.  **Static Analysis (Crucial):**
    We use `shellcheck` to ensure code quality. Please install it and run:
    ```bash
    shellcheck vopk
    ```
    *All PRs must pass ShellCheck without warnings.*

2.  **Manual Testing:**
    Always test your changes with the `--dry-run` flag first:
    ```bash
    ./vopk install <package> --dry-run --debug
    ```

### Bash Style Guide
To keep the codebase clean and maintainable, please follow these rules:

1.  **Indentation:** Use **4 spaces**. No tabs.
2.  **Variables:**
    * Global variables: `UPPER_CASE` (e.g., `VOPK_VERSION`).
    * Local variables: `snake_case` (e.g., `local pkg_name`).
    * **ALWAYS** use `local` inside functions to avoid scope pollution.
3.  **Functions:**
    * Core functions: `cmd_action` (e.g., `cmd_install`).
    * Helper functions: `util_name` or just descriptive names.
4.  **Output:**
    * **Do not use** `echo` or `printf` directly for UI.
    * Use the internal API: `log`, `log_success`, `warn`, `die`, `ui_row`.
5.  **Safety:**
    * Always quote your variables: `"$var"`.
    * Use `[[ ... ]]` for conditions, not `[ ... ]`.

---

## 📬 Submission Guidelines

### Commit Messages
We follow the **Conventional Commits** specification. This helps us generate changelogs automatically.

* `feat: add support for Nix package manager`
* `fix: resolve crash on Fedora 39`
* `docs: update plugin guide`
* `style: fix indentation in main loop`
* `refactor: optimize dependency detection`

### Pull Request Process
1.  **Update Documentation:** If you added a new feature or changed behavior, update `README.md` or `plugin/docs.md`.
2.  **Verify Compatibility:** Ensure your code works on at least one Debian-based and one Arch-based system (or use Dry Run logic).
3.  **Link Issues:** In your PR description, link to the issue you are fixing (e.g., "Fixes #42").
4.  **Review:** A maintainer will review your code. Be open to feedback!

---

## 🌟 Recognition
Contributors who have their PRs merged will be added to the `AUTHORS` file and listed in the release notes.

**Happy Hacking!** 💻