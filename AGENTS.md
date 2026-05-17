# AGENTS.md

## Cursor Cloud specific instructions

This is a **dotfiles/rice repository** for Arch Linux + Hyprland (Wayland compositor). It is not a traditional application with a build system or dev server. The codebase consists of shell scripts, Python (GTK4/Libadwaita), QML (Quickshell), and configuration files.

### Repository structure

- `install/` — Installer scripts and test suites
- `cloudyy_scripts/` — Runtime scripts (theme controller, Cloud Center, rofi menus, bridge scripts)
- `.config/` — Dotfiles for Hyprland, Quickshell, kitty, rofi, matugen, etc.

### Running tests

Three test scripts live in `install/` and can be run on any Linux system (no Arch/Hyprland required):

```bash
bash install/test-install.sh           # Full pre-flight test suite (44 tests)
bash install/test-quickshell-only.sh   # Verifies quickshell is the only active shell path
bash install/test-no-waybar-bindings.sh # Verifies no legacy waybar bindings remain
```

The installer also supports `./install/install.sh --dry-run` to preview the installation plan without executing anything.

### Linting

- **Shell scripts**: `shellcheck <script.sh>` — all scripts under `install/` and `cloudyy_scripts/` should be checked.
- **Python**: `ruff check cloudyy_scripts/cloud-center-v2/` — E402 (import order) and F401 (unused imports) are expected due to GTK's `gi.require_version()` pattern.
- **QML**: Requires the Qt6 SDK (`qmlformat`, `qml`), which is not available in the cloud VM. QML files cannot be linted in this environment.

### Environment limitations

- The GUI components (Hyprland, Quickshell, Cloud Center GTK4 app, Rofi) cannot run in the cloud VM — they require a Wayland display server and GPU.
- Python `gi` (PyGObject/GTK4/Libadwaita) imports will fail at runtime since GTK4 libraries are not installed. Syntax/compile checks (`python3 -m py_compile`) and `ruff` work fine.
- `pacman` (Arch Linux package manager) is not available; system-requirement checks in the test suite will warn but not fail.
