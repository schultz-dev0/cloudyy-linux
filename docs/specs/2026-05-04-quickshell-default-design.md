# Quickshell-Only Shell Wiring Design

## Problem

The repository still treats the desktop shell as a selectable profile even though quickshell is now the intended default. That switching logic currently spans installer prompts, persisted shell-stack state, package resolution, generated Hyprland autostart fragments, and theme/controller bridge wiring.

The goal of this change is to remove that switching logic entirely while keeping the current quickshell behavior intact. This change does **not** remove remaining Waybar, SwayNC, or related assets from the repository yet; it only removes their role in active installer/runtime selection.

## Approved Scope

1. Remove the shell-stack/profile selection flow.
2. Make quickshell the only supported shell path in installer and runtime wiring.
3. Keep rofi as launcher and power menu for now.
4. Leave leftover Waybar/SwayNC assets in the repo temporarily, but make them inactive.

## Current State

The switching logic currently exists in several layers:

- `install/install.sh` runs a shell-stack selection phase and exports the chosen profile.
- `install/hyprland-install.sh` reads shell-stack state to decide which shell packages to install.
- `install/select-shell-stack.sh`, `install/apply-shell-stack.sh`, and `install/shell-stack.conf` implement profile persistence and generated autostart output.
- `~/.config/hypr/hyprland.conf` sources `~/.config/hypr/source/shell-stack.conf`, which is generated from the selected profile.
- `install/widget_bridge.sh` rewrites theme/controller and Cloud Center wiring based on the chosen profile.

This makes quickshell the default in practice but not the only supported code path.

## Proposed Design

### 1. Installer

Remove the shell-stack selection phase from `install/install.sh`.

Instead of exporting `CLOUDYY_SHELL_STACK` or reading `~/.local/share/cloudyy/shell-stack`, the installer should treat quickshell as part of the normal expected interface stack. Package installation should resolve quickshell directly without profile indirection.

### 2. Package Resolution

Eliminate shell-stack-based package lookup from `install/hyprland-install.sh`.

`quickshell` should be installed through a fixed package list rather than `PROFILE_*` variables sourced from `install/shell-stack.conf`. This removes the last active package-selection dependency on profile state.

### 3. Hyprland Runtime Wiring

Replace the generated shell-stack autostart path with a static quickshell source file tracked in the repository.

Hyprland should always source a fixed file that contains the quickshell autostart command. The sourced file should preserve the current quickshell startup behavior, including the effective `qs -d` launch command, so the refactor does not change user-visible shell behavior.

As part of this change:

- remove `install/select-shell-stack.sh`
- remove `install/apply-shell-stack.sh`
- remove `install/shell-stack.conf`
- stop generating `~/.config/hypr/source/shell-stack.conf`
- update the Hyprland source chain to point at the new fixed quickshell autostart file

### 4. Theme / Bridge / Cloud Center Wiring

Make `install/widget_bridge.sh` unconditionally target the quickshell path.

It should no longer accept or interpret a shell profile. Instead, it should always wire:

- the quickshell bridge script into `theme_controller.sh`
- the quickshell tab into Cloud Center

This keeps theme and control-surface behavior consistent with the new single-shell model.

### 5. Compatibility Boundary

This refactor intentionally does not delete all Waybar/SwayNC files yet.

Those files may still exist in the repository for a later cleanup pass, but after this change:

- installer flow no longer offers them as a supported shell choice
- runtime startup wiring no longer selects them
- profile/state machinery no longer exists

That leaves them as inactive leftovers instead of supported alternatives.

## Data Flow After Change

1. Installer runs without a shell selection prompt.
2. Package installation includes quickshell directly.
3. Dotfiles deployment places a static quickshell autostart source file in the Hyprland config tree.
4. Hyprland always sources that fixed file.
5. Theme/controller integration always points to quickshell.

There is no shell-profile state file and no generated autostart profile output.

## Error Handling and Migration Expectations

- Re-running the installer after pulling this change should still produce a valid Hyprland config.
- Existing users should not need to choose a shell stack anymore.
- Any obsolete shell-stack state file may remain on disk harmlessly, but no active code should read it.
- If bridge rewiring fails, it should fail explicitly rather than silently pretending another shell path exists.

## Validation

Verify the implementation by checking that:

1. `install/install.sh` no longer prompts for shell-stack selection.
2. `install/hyprland-install.sh` no longer reads shell-stack environment or state.
3. No active installer/runtime path references `select-shell-stack.sh`, `apply-shell-stack.sh`, or `shell-stack.conf`.
4. Hyprland sources a fixed quickshell autostart file instead of generated profile output.
5. `install/widget_bridge.sh` always wires quickshell.
6. README text is updated anywhere it still describes shell switching or the old default-selection behavior.

## Out of Scope

- Deleting all Waybar, SwayNC, swayosd, or preview assets from the repository
- Replacing rofi as launcher or power menu
- Broader cleanup of legacy shell-specific scripts unless they are directly required to remove switching logic

## Rationale

This approach removes the real source of inconsistency: the code still models multiple supported shell stacks even though the project has already decided on quickshell. Replacing that subsystem with one fixed quickshell path produces simpler installer behavior, simpler runtime wiring, and a clearer default without forcing a full legacy-asset purge in the same change.
