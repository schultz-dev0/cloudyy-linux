# Install Script Audit — Design Spec
**Date:** 2026-05-13  
**Approach:** Approach B — fix all bugs + targeted consolidation  
**Scope:** `install/` suite — all scripts audited and fixed  

---

## Problem Statement

The `install/` suite has accumulated a set of critical bugs (test failures, crashes on fresh
installs, never-called scripts), dirty-system fragility (double prompts, unattended breakage,
backup collisions), and missing laptop-specific support (hybrid GPU PRIME, power management,
touchpad). This spec describes all fixes and additions in one cohesive pass.

---

## Files Changed

| File | Changes |
|------|---------|
| `install/dependencies.conf` | Add legacy aliases + `FULL_GROUP` |
| `install/install.sh` | UNATTENDED propagation, `phase_laptop`, `phase_schema`, deduplicate phase_shell |
| `install/deploy-dotfiles.sh` | UNATTENDED passthrough, backup path fix, remove duplicate `setup_shell`, guard deploy_defaults |
| `install/hyprland-install.sh` | Hybrid PRIME GPU launcher, `nvidia-prime` in NVIDIA deps, touchpad config via `phase_laptop` helper |
| `install/seed-required-applications.sh` | Fix Cloud-center.desktop copy-paste |
| `install/widget_bridge.sh` | Non-fatal on missing WIDGETS_BRIDGE pattern |
| `install/setup-system-theme.sh` | UNATTENDED passthrough, fix heredoc indentation |
| `install/test-install.sh` | No changes needed — aliases added to dependencies.conf fix all test failures |

---

## Section 1: Critical Bug Fixes

### 1.1 `dependencies.conf` — missing array aliases

`test-install.sh` tests reference: `CORE_PACKAGES`, `INTERFACE_PACKAGES`, `UTILITY_PACKAGES`,
`AUR_PACKAGES`, `AUDIO_PACKAGES`, `FULL_GROUP`. None exist. Add at the bottom of `dependencies.conf`:

```bash
# === ALIASES FOR test-install.sh COMPATIBILITY ===
CORE_PACKAGES=(
  "${MANDATORY_OFFICIAL_COMPOSITOR[@]}"
  "${MANDATORY_OFFICIAL_DAEMONS[@]}" "${MANDATORY_AUR_DAEMONS[@]}"
  "${MANDATORY_OFFICIAL_SHELL[@]}"
  "${MANDATORY_OFFICIAL_SYSTEM[@]}"
)
INTERFACE_PACKAGES=(
  "${MANDATORY_OFFICIAL_INTERFACE[@]}" "${MANDATORY_AUR_INTERFACE[@]}"
)
UTILITY_PACKAGES=(
  "${MANDATORY_OFFICIAL_SCREENSHOT[@]}"
  "${MANDATORY_OFFICIAL_MONITORING[@]}"
)
AUR_PACKAGES=(
  "${MANDATORY_AUR_DAEMONS[@]}"
  "${MANDATORY_AUR_INTERFACE[@]}"
  "${MANDATORY_AUR_THEMING[@]}"
  "${STANDARD_INSTALL_AUR[@]}"
)
AUDIO_PACKAGES=( "${MANDATORY_OFFICIAL_AUDIO[@]}" )

FULL_GROUP=(
  "${STANDARD_GROUP[@]}"
  "${ADDON_OFFICIAL_OBS[@]}"
  "${ADDON_OFFICIAL_GAMING[@]}"  "${ADDON_AUR_GAMING[@]}"
  "${ADDON_OFFICIAL_OFFICE[@]}"
  "${ADDON_OFFICIAL_DEV[@]}"     "${ADDON_AUR_DEV[@]}"
)
```

Also add `OPTIONAL_AUR_GAMING` and `OPTIONAL_OFFICIAL_GAMING` aliases (referenced in test line 173):
```bash
OPTIONAL_AUR_GAMING=( "${ADDON_AUR_GAMING[@]}" )
OPTIONAL_OFFICIAL_GAMING=( "${ADDON_OFFICIAL_GAMING[@]}" )
```

### 1.2 `seed-required-applications.sh` — Cloud-center.desktop copy-paste bug

The `Cloud-center.desktop` entry has `Name=Rusty Keys`, `Exec=rusty_keys`, and wrong WMClass.
Fix to:
```ini
Name=Cloud Center
Comment=Cloud Center — Hyprland session manager
Exec=bash -c "python3 ~/cloudyy_scripts/cloud-center-v2/cloud-center.py"
StartupWMClass=org.cloudyy.cloudcenter
X-GNOME-WMClass=org.cloudyy.cloudcenter
```

### 1.3 `deploy-dotfiles.sh` `deploy_defaults()` — crash on missing default-theme dir

Guard the `cp` call:
```bash
if [[ -f "${defaults_dir}/hyprland.conf" ]]; then
  cp "${defaults_dir}/hyprland.conf" "$hypr_conf"
  log_ok "hyprland.conf deployed (default)."
else
  log_warn "No default hyprland.conf in ${defaults_dir} — Hyprland may not start until configured."
fi
```

### 1.4 `schema_settings.sh` never called

Add to `deploy-dotfiles.sh` main():
```bash
"${REPO_DIR}/install/schema_settings.sh" || log_warn "schema_settings.sh encountered issues (non-fatal)"
```
Also add a `phase_schema` to `install.sh` (after `phase_dotfiles`) that calls it as a standalone phase so the user can retry it independently.

### 1.5 `widget_bridge.sh` — fatal exit on missing WIDGETS_BRIDGE line

Change `verify_controller_bridge()` and `update_cloud_center()` to warn instead of exit:
```bash
verify_controller_bridge() {
  if grep -Fxq "WIDGETS_BRIDGE=\"${BRIDGE_SCRIPT}\"" "$file"; then
    echo "[✓] Wired quickshell bridge into $(basename "$file")"
  else
    echo "[!] Could not verify bridge wire in $(basename "$file") — may need manual fix" >&2
  fi
}
```
Also add a guard for the case where the sed pattern doesn't exist (i.e. `WIDGETS_BRIDGE=` line absent entirely): pre-check and `log_warn` + return 0.

---

## Section 2: Dirty-System & `--unattended` Fixes

### 2.1 UNATTENDED propagation

In `install.sh`, export the flag before calling any sub-script:
```bash
export CLOUDYY_UNATTENDED="${UNATTENDED}"
```

In every sub-script that has `read -rp`, guard it:
```bash
if [[ "${CLOUDYY_UNATTENDED:-0}" == "1" ]]; then
  log "Unattended mode — proceeding automatically."
else
  read -rp "Proceed? [Y/n]: " _confirm
  [[ "${_confirm,,}" == "n" ]] && { log "Cancelled."; exit 0; }
fi
```

Files affected: `deploy-dotfiles.sh` (main prompt), `setup-system-theme.sh`
(Hyprland config optional prompt).

Also add `--unattended` as a CLI flag to `deploy-dotfiles.sh` for standalone use:
sets `CLOUDYY_UNATTENDED=1` before main().

### 2.2 Backup path collision fix

Change `backup_if_needed()` to mirror the source tree under `$BACKUP_DIR` instead of a flat basename:
```bash
local rel_path="${target#${HOME}/}"
local dest="${BACKUP_DIR}/${rel_path}"
mkdir -p "$(dirname "$dest")"
mv "$target" "$dest"
```

This means `.config/hypr` backs up as `${BACKUP_DIR}/.config/hypr/` — no collisions.

### 2.3 `setup-system-theme.sh` heredoc indentation

Remove the 4-space indent from the `${SHELL_THEME_BEGIN}` / `${SHELL_THEME_END}` lines in
the heredoc so the written marker exactly matches the guard variable (cosmetic, prevents
future confusion).

### 2.4 Deduplicate shell setup

`setup_shell` in `deploy-dotfiles.sh` runs during `phase_dotfiles` (before packages), and
`phase_shell` in `install.sh` runs post-packages. They do the same work.

When called from `install.sh`: remove `setup_shell` from `deploy-dotfiles.sh`'s `main()` —
`install.sh`'s `phase_shell` handles it after packages are installed.

When `deploy-dotfiles.sh` is run standalone: keep `setup_shell` in the standalone path (since
there's no install.sh driving it).

Implementation: check `CLOUDYY_INSTALL_ORCHESTRATED` env var (set by install.sh before calling
sub-scripts) to decide whether to run `setup_shell`:
```bash
[[ "${CLOUDYY_INSTALL_ORCHESTRATED:-0}" != "1" ]] && setup_shell
```

---

## Section 3: Laptop Support

### 3.1 Hybrid Intel+NVIDIA PRIME GPU launcher

Add `nvidia-prime` to `OFFICIAL_GPU_NVIDIA` in `dependencies.conf`.

In `detect_and_install_gpu()`, detect the hybrid combo:
```bash
if (( has_nvidia && has_intel )); then
  # Hybrid Optimus laptop
  write_gpu_launcher "nvidia-prime"
elif (( has_nvidia )); then
  write_gpu_launcher "nvidia"
elif (( has_amd )); then
  write_gpu_launcher "amd"
elif (( has_intel )); then
  write_gpu_launcher "intel"
fi
```

In `write_gpu_launcher()`, add a `nvidia-prime` case:
```bash
nvidia-prime)
  # Intel iGPU drives display; NVIDIA available via PRIME offload
  cat >>"$launcher" <<'PRIME'
# Intel+NVIDIA hybrid (Optimus/PRIME)
# iGPU drives the display; NVIDIA GPU available via PRIME offload.
export LIBVA_DRIVER_NAME=iHD
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
export WLR_NO_HARDWARE_CURSORS=1
PRIME
  # Write environment.d
  cat >"${env_d}/nvidia-prime-wayland.conf" <<'ENVD'
__NV_PRIME_RENDER_OFFLOAD=1
__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
__GLX_VENDOR_LIBRARY_NAME=nvidia
ENVD
  ;;
```

### 3.2 `power-profiles-daemon`

Add to `MANDATORY_OFFICIAL_SYSTEM` in `dependencies.conf`:
```bash
"power-profiles-daemon"
```

Enable in `phase_services` in `install.sh`:
```bash
"power-profiles-daemon.service"
```

Zero changes needed to rofi power menu — it already uses `powerprofilesctl`.

### 3.3 Laptop touchpad detection and config

Add `phase_laptop()` to `install.sh` (registered after `phase_shell`):

```bash
phase_laptop() {
  # Skip if no battery found — not a laptop
  if ! ls /sys/class/power_supply/BAT* &>/dev/null; then
    log_ok "No battery detected — skipping laptop config."
    return 0
  fi

  log "Laptop detected — deploying touchpad config..."

  local hypr_dir="${HOME}/.config/hypr"
  local input_conf="${hypr_dir}/input-overrides.conf"
  local hypr_conf="${hypr_dir}/hyprland.conf"

  mkdir -p "$hypr_dir"

  if [[ ! -f "$input_conf" ]]; then
    cat >"$input_conf" <<'EOF'
# cloudyy-linux: laptop input overrides (generated by installer)
input {
    touchpad {
        natural_scroll = true
        tap-to-click = true
        tap-and-drag = true
        drag_lock = true
        disable_while_typing = true
        scroll_factor = 1.0
    }
    sensitivity = 0
}

gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
    workspace_swipe_distance = 300
    workspace_swipe_cancel_ratio = 0.5
}
EOF
    log_ok "Touchpad config written: ${input_conf}"
  else
    log_ok "Touchpad config already exists — skipping."
  fi

  # Idempotently source from hyprland.conf
  if [[ -f "$hypr_conf" ]] && ! grep -q "input-overrides.conf" "$hypr_conf"; then
    printf '\n# cloudyy-linux laptop: touchpad + gestures\nsource = %s\n' "$input_conf" >>"$hypr_conf"
    log_ok "Touchpad config sourced in hyprland.conf."
  fi
}
```

Register in PHASE_IDS after "shell":
```bash
declare -a PHASE_IDS=(
  "preflight" "dotfiles" "packages" "schema" "shell" "laptop" "keyring" "theme_init" "services" "finalize"
)
```

---

## Testing

After all changes, run:
```bash
cd /home/schultz/cloudyy-linux/install
bash test-install.sh
```

Expected: all tests pass, including the package array tests that currently fail.

---

## Non-Goals

- No new script architecture (no new files beyond the existing suite)
- No changes to quickshell, waybar, or theme controller logic
- No gaming/OBS/office addon installation logic
