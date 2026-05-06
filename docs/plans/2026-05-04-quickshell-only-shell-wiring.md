# Quickshell-Only Shell Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the shell-stack/default-vs-quickshell switching logic so the repo always installs and wires quickshell as the only active shell path.

**Architecture:** Replace the generated `shell-stack.conf` flow with one fixed quickshell autostart file tracked in the repo, then simplify installer/package wiring so it no longer persists or reads shell-profile state. Keep legacy Waybar/SwayNC assets in the repository for now, but detach them from installer/runtime selection so they are inert leftovers instead of supported alternatives.

**Tech Stack:** Bash installer scripts, Hyprland `.conf` + Lua config, Python Cloud Center wiring, Markdown docs

---

## File Structure

- **Create:** `.config/hypr/source/quickshell.conf` — the one authoritative Hyprland fragment that autostarts quickshell.
- **Modify:** `.config/hypr/hyprland.conf` — source the new fixed quickshell fragment instead of `source/shell-stack.conf`.
- **Modify:** `.config/hypr/source/autostart.conf` — update comments so they describe the fixed quickshell file, not generated shell-stack output.
- **Modify:** `.config/hypr/.hyprlua/autostart.lua` — keep Lua-path comments and quickshell command aligned with the new fixed runtime path.
- **Delete:** `.config/hypr/source/shell-stack.conf` — remove the generated-profile artifact from the repo.
- **Modify:** `install/install.sh` — remove the shell-stack phase and all state/export plumbing tied to profile selection.
- **Modify:** `install/hyprland-install.sh` — install quickshell directly and delete shell-stack-specific package resolution.
- **Modify:** `install/dependencies.conf` — update comments so interface packages describe the new fixed quickshell model.
- **Delete:** `install/select-shell-stack.sh`, `install/apply-shell-stack.sh`, `install/shell-stack.conf` — remove the obsolete selection/generation subsystem.
- **Modify:** `install/deploy-dotfiles.sh` — stop calling `apply-shell-stack.sh`; call the fixed quickshell bridge wiring directly and keep immediate theme seeding explicit.
- **Modify:** `install/widget_bridge.sh` — make it idempotently wire quickshell with no profile argument.
- **Modify:** `README.md` — remove any text that still implies shell switching or an old active default path.

### Task 1: Replace generated shell-stack autostart with a fixed quickshell source

**Files:**
- Create: `.config/hypr/source/quickshell.conf`
- Modify: `.config/hypr/hyprland.conf`
- Modify: `.config/hypr/source/autostart.conf`
- Modify: `.config/hypr/.hyprlua/autostart.lua`
- Delete: `.config/hypr/source/shell-stack.conf`

- [ ] **Step 1: Capture the existing shell-stack references in Hyprland config**

Run:

```bash
rg -n 'shell-stack\.conf|Shell stack|qs -d' .config/hypr
```

Expected: matches in `hyprland.conf`, `source/autostart.conf`, `.hyprlua/autostart.lua`, and `.config/hypr/source/shell-stack.conf`.

- [ ] **Step 2: Create the fixed quickshell autostart fragment**

Add this file:

```conf
# Quickshell autostart — fixed default shell
exec-once = env QS_NO_RELOAD_POPUP=1 qs -d
```

Path:

```text
.config/hypr/source/quickshell.conf
```

- [ ] **Step 3: Repoint the Hyprland config chain at the fixed file**

Update `.config/hypr/hyprland.conf` so the shell source block becomes:

```conf
# Quickshell autostart — fixed default shell
source = ~/.config/hypr/source/quickshell.conf
```

Update `.config/hypr/source/autostart.conf` comments to:

```conf
# Quickshell autostart lives in source/quickshell.conf:
# exec-once = env QS_NO_RELOAD_POPUP=1 qs -d
```

Update `.config/hypr/.hyprlua/autostart.lua` so the comment and command read:

```lua
-- Autostart — equivalent of exec-once entries
-- Sources: user-configs/user_autostart.conf + source/quickshell.conf

    -- Quickshell autostart (mirrors source/quickshell.conf)
    hl.exec_cmd("env QS_NO_RELOAD_POPUP=1 qs -d")
```

- [ ] **Step 4: Delete the generated shell-stack fragment from the repo**

Run:

```bash
git rm .config/hypr/source/shell-stack.conf
```

Expected: `git status --short` shows the file as deleted and `quickshell.conf` as added.

- [ ] **Step 5: Verify Hyprland now points only at the fixed quickshell file**

Run:

```bash
rg -n 'shell-stack\.conf|source/quickshell\.conf|QS_NO_RELOAD_POPUP=1 qs -d' .config/hypr
```

Expected:
- `source/quickshell.conf` appears in `hyprland.conf`, `source/autostart.conf`, and `.hyprlua/autostart.lua`
- `shell-stack.conf` no longer appears anywhere under `.config/hypr`

- [ ] **Step 6: Commit the runtime wiring change**

Run:

```bash
git add .config/hypr/hyprland.conf \
        .config/hypr/source/autostart.conf \
        .config/hypr/.hyprlua/autostart.lua \
        .config/hypr/source/quickshell.conf
git commit -m "refactor: make quickshell autostart static"
```

Expected: one commit containing only the fixed Hyprland shell wiring changes.

### Task 2: Remove shell-stack selection and install quickshell directly

**Files:**
- Modify: `install/install.sh`
- Modify: `install/hyprland-install.sh`
- Modify: `install/dependencies.conf`
- Delete: `install/select-shell-stack.sh`
- Delete: `install/apply-shell-stack.sh`
- Delete: `install/shell-stack.conf`

- [ ] **Step 1: Capture every active installer reference to shell-stack state**

Run:

```bash
rg -n 'shell-stack|select-shell-stack|apply-shell-stack|CLOUDYY_SHELL_STACK' install
```

Expected: matches in `install.sh`, `hyprland-install.sh`, `dependencies.conf`, and the three soon-to-be-deleted shell-stack files.

- [ ] **Step 2: Remove the shell-stack phase from the master installer**

Update `install/install.sh` so the package phase no longer exports `CLOUDYY_SHELL_STACK`:

```bash
# --- Phase: Packages ---------------------------------------------------------
phase_packages() {
  bash "${SCRIPT_DIR}/hyprland-install.sh"
}
```

Update the phase registry so it becomes:

```bash
declare -a PHASE_IDS=(
  "preflight"
  "dotfiles"
  "packages"
  "services"
  "finalize"
)

declare -A PHASE_LABELS=(
  [preflight]="System Preflight Checks"
  [dotfiles]="Dotfiles Deployment"
  [packages]="Hardware & Package Installation"
  [services]="Service Configuration"
  [finalize]="Finalization"
)
```

Also remove the entire `phase_shell_stack()` function.

- [ ] **Step 3: Install quickshell directly in the package layer**

Update `install/dependencies.conf` comments to describe quickshell as part of the fixed interface path:

```bash
# --- Desktop Interface --------------------------------------------------------
# Core interactive shell components for the quickshell-based default desktop.
MANDATORY_OFFICIAL_INTERFACE=(
  "rofi"       # App launcher (keybinds depend on this)
  "swww"       # Wallpaper daemon
  "quickshell" # Bar / notifications / shell UI
)
```

Then delete the shell-stack resolution block from `install/hyprland-install.sh` so the installer goes straight from `show_summary` to package installation:

```bash
  log_section "Installing — Official Packages"
  pacman_install "Compositor" "${MANDATORY_OFFICIAL_COMPOSITOR[@]}"
  pacman_install "Daemons" "${MANDATORY_OFFICIAL_DAEMONS[@]}"
  pacman_install "Audio" "${MANDATORY_OFFICIAL_AUDIO[@]}"
  pacman_install "Interface" "${MANDATORY_OFFICIAL_INTERFACE[@]}"
```

Remove the old `STACK_OFFICIAL` / `STACK_AUR` locals and the `pacman_install "Shell Stack"` line.

- [ ] **Step 4: Delete the obsolete selection/generation subsystem**

Run:

```bash
git rm install/select-shell-stack.sh install/apply-shell-stack.sh install/shell-stack.conf
```

Expected: only those three files are staged as deleted.

- [ ] **Step 5: Verify the installer is free of shell-stack plumbing**

Run:

```bash
rg -n 'shell-stack|select-shell-stack|apply-shell-stack|CLOUDYY_SHELL_STACK' install
bash -n install/install.sh install/hyprland-install.sh
```

Expected:
- `rg` returns no matches in active installer code
- `bash -n` prints nothing and exits successfully

- [ ] **Step 6: Commit the installer simplification**

Run:

```bash
git add install/install.sh install/hyprland-install.sh install/dependencies.conf
git commit -m "refactor: remove shell-stack installer flow"
```

Expected: one commit containing the installer/package cleanup plus the three deletions.

### Task 3: Rewire deployment helpers and align the docs with a quickshell-only default

**Files:**
- Modify: `install/deploy-dotfiles.sh`
- Modify: `install/widget_bridge.sh`
- Modify: `README.md`

- [ ] **Step 1: Make widget bridge wiring unconditional**

Replace the profile-driven parts of `install/widget_bridge.sh` with fixed quickshell values:

```bash
#!/usr/bin/env bash
set -euo pipefail

THEME_CONTROLLER_HOME="${HOME}/cloudyy_scripts/theme_controller.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_CONTROLLER_REPO="$(cd "$SCRIPT_DIR/.." && pwd)/cloudyy_scripts/theme_controller.sh"
BRIDGE_SCRIPT="${HOME}/cloudyy_scripts/bridge_scripts/bridge_quickshell.sh"
```

And update the Cloud Center rewrite block to always enforce:

```bash
sed -i 's|^ACTIVE_SHELL_TAB = ".*"|ACTIVE_SHELL_TAB = "quickshell"|' "$py_file"
```

Delete the `PROFILE` argument handling, the `default` tab fallback, and any profile-based conditionals.

- [ ] **Step 2: Replace the apply-shell-stack hook in dotfiles deployment**

Update the end of `install/deploy-dotfiles.sh` so it directly runs the fixed quickshell bridge wiring and immediate theme restore:

```bash
  local _self_dir
  _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "${_self_dir}/widget_bridge.sh" ]]; then
    bash "${_self_dir}/widget_bridge.sh" || log_warn "widget_bridge.sh failed (non-fatal)"
  fi

  if [[ -x "${HOME}/cloudyy_scripts/theme_controller.sh" ]]; then
    "${HOME}/cloudyy_scripts/theme_controller.sh" restore >/dev/null 2>&1 || \
      log_warn "theme_controller restore failed (non-fatal)"
  fi
```

This block should replace the old `apply-shell-stack.sh` invocation entirely.

- [ ] **Step 3: Update README text so it no longer implies shell switching**

Adjust the intro/usage text to describe quickshell as the active shell path and mark Waybar material as legacy. Replace the usage bullets with:

```markdown
- **Theme toggle**: `~/cloudyy_scripts/theme_controller.sh toggle`
- **Rofi launcher**: `Super + Alt + Space` — includes app launcher, keybind help, theme picker, and more
- **Quickshell shell**: bar, notifications, and shell UI are provided by quickshell by default
- **Waybar presets**: legacy assets kept in-repo during the transition; not part of the active default shell path
```

- [ ] **Step 4: Run the repo-native verification commands for the new fixed path**

Run:

```bash
rg -n 'shell-stack|select-shell-stack|apply-shell-stack|CLOUDYY_SHELL_STACK' install .config/hypr cloudyy_scripts README.md
bash -n install/install.sh install/hyprland-install.sh install/deploy-dotfiles.sh install/widget_bridge.sh install/setup-system-theme.sh
git diff --check
```

Expected:
- `rg` returns no matches in active code/docs
- `bash -n` prints nothing and exits successfully
- `git diff --check` prints nothing

- [ ] **Step 5: Commit the deployment/doc cleanup**

Run:

```bash
git add install/deploy-dotfiles.sh install/widget_bridge.sh README.md
git commit -m "refactor: wire deploy for quickshell only"
```

Expected: one commit containing the fixed deploy hook, fixed bridge script, and README wording updates.
