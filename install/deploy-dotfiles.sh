#!/usr/bin/env bash
# =============================================================================
# deploy-dotfiles.sh — Dotfiles Deployment
# =============================================================================
# Clones (or updates) cloudyy-linux and symlinks dotfiles into $HOME.
# Existing files are backed up before being replaced — nothing is silently
# destroyed.
#
# Called by install.sh. Can also be run standalone.
# =============================================================================

set -euo pipefail -E

# --- Configuration -----------------------------------------------------------
readonly REPO_URL="https://github.com/schultz-dev0/cloudyy-linux"
readonly REPO_DIR="${HOME}/cloudyy-linux"
readonly BACKUP_DIR="${HOME}/.config/cloudyy-backups/$(date +%Y%m%d_%H%M%S)"

# --- Colors (TTY-aware) ------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' CYAN=$'\e[1;36m' BOLD=$'\e[1m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

# --- Logging -----------------------------------------------------------------
_ts() { date '+%H:%M:%S'; }
log()         { printf '%s[*]%s  [%s] %s\n'              "$BLUE"   "$RESET" "$(_ts)" "$1"; }
log_ok()      { printf '%s[✓]%s  [%s] %s\n'              "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_warn()    { printf '%s[!]%s  [%s] %s\n'              "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error()   { printf '%s[✗]%s  [%s] %s\n'              "$RED"    "$RESET" "$(_ts)" "$1" >&2; }
log_skip()    { printf '%s[-]%s  [%s] %s %s(unchanged)%s\n' "$CYAN" "$RESET" "$(_ts)" "$1" "$YELLOW" "$RESET"; }
log_section() { printf '\n%s%s── %s%s\n'                  "$BOLD"   "$CYAN"  "$1"     "$RESET"; }

# --- Guards ------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  log_error "Do not run as root."
  exit 1
fi

_err_handler() {
  log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  log_error "  in ${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}:${FUNCNAME[1]:-main}"
}
trap '_err_handler' ERR

# =============================================================================
# HELPERS
# =============================================================================

# Back up a path if it exists and is not already a symlink to our repo
backup_if_needed() {
  local target="$1"

  # Nothing to back up if it doesn't exist
  [[ -e "$target" || -L "$target" ]] || return 0

  # If it's already a symlink pointing into our repo dir, leave it alone
  if [[ -L "$target" ]]; then
    local link_dest
    link_dest="$(readlink -f "$target" 2>/dev/null)" || true
    if [[ "$link_dest" == "${REPO_DIR}"* ]]; then
      return 0 # Already linked to our repo — safe to re-link
    fi
  fi

  # It's a real file/dir that will be replaced — back it up, mirroring its path
  local rel_path="${target#${HOME}/}"
  local dest="${BACKUP_DIR}/${rel_path}"
  mkdir -p "$(dirname "$dest")"
  mv "$target" "$dest"
  log_warn "Backed up: ${rel_path} → ${BACKUP_DIR}/${rel_path}"
}

# Create a symlink, backing up whatever was there first
safe_symlink() {
  local src="$1" # Source (inside repo)
  local dst="$2" # Destination (in $HOME or $HOME/.config)

  if [[ ! -e "$src" ]]; then
    log_warn "Source not found, skipping: ${src}"
    return 0
  fi

  backup_if_needed "$dst"
  ln -snf "$src" "$dst"
  log_ok "Linked: $(basename "$dst")"
}

# =============================================================================
# STEP 1: Clone or Update Repository
# =============================================================================

sync_repo() {
  log_section "Repository"

  if [[ -d "${REPO_DIR}/.git" ]]; then
    log "Repository exists — pulling latest changes..."
    if git -C "$REPO_DIR" pull --ff-only; then
      log_ok "Repository updated."
    else
      log_warn "git pull failed (local changes?). Using existing state."
    fi
  else
    log "Cloning ${REPO_URL}..."
    if git clone --depth 1 "$REPO_URL" "$REPO_DIR"; then
      log_ok "Repository cloned to: ${REPO_DIR}"
    else
      log_error "Failed to clone repository. Check your internet connection and the URL."
      exit 1
    fi
  fi
}

# =============================================================================
# STEP 2: Symlink Home Dotfiles (.zshrc, .bashrc, etc.)
# =============================================================================

link_home_dotfiles() {
  log_section "Home Dotfiles"

  local linked=0
  local skipped=0

  while IFS= read -r -d '' dotfile; do
    local filename
    filename="$(basename "$dotfile")"
    safe_symlink "$dotfile" "${HOME}/${filename}"
    ((++linked))
  done < <(find "$REPO_DIR" -maxdepth 1 \
    -name ".*" \
    ! -name ".config" \
    ! -name ".git" \
    ! -name ".gitignore" \
    ! -name ".gitmodules" \
    ! -name ".local" \
    -print0 2>/dev/null)

  if ((linked == 0)); then
    log_warn "No home dotfiles found in repository root."
  else
    log_ok "${linked} home dotfile(s) linked."
  fi
}

# =============================================================================
# STEP 3: Symlink .config Directories
# =============================================================================

link_config_dirs() {
  log_section ".config Directories"

  local config_src="${REPO_DIR}/.config"
  if [[ ! -d "$config_src" ]]; then
    log_warn "No .config directory found in repository — skipping."
    return 0
  fi

  mkdir -p "${HOME}/.config"
  local linked=0

  for dir in "${config_src}"/*/; do
    [[ -d "$dir" ]] || continue
    local dirname
    dirname="$(basename "$dir")"

    # Skip legacy shell directories - quickshell is the only active shell
    if [[ "$dirname" == "waybar" || "$dirname" == "swaync" ]]; then
      continue
    fi

    safe_symlink "$dir" "${HOME}/.config/${dirname}"
    ((++linked))
  done

  if ((linked == 0)); then
    log_warn "No directories found in .config."
  else
    log_ok "${linked} .config directory/directories linked."
  fi
}

# =============================================================================
# STEP 4: Symlink Additional Known Directories
# =============================================================================

link_extra_dirs() {
  log_section "Extra Directories"

  # Wallpapers
  if [[ -d "${REPO_DIR}/Wallpapers" ]]; then
    safe_symlink "${REPO_DIR}/Wallpapers" "${HOME}/Wallpapers"
  fi

  # cloudyy_scripts — also make them executable
  if [[ -d "${REPO_DIR}/cloudyy_scripts" ]]; then
    safe_symlink "${REPO_DIR}/cloudyy_scripts" "${HOME}/cloudyy_scripts"
    find "${REPO_DIR}/cloudyy_scripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \; 2>/dev/null &&
      log_ok "cloudyy_scripts made executable." ||
      true
  fi

  # pywalfox native messaging host — symlink only this file, not the whole zen dir
  local pywalfox_src="${REPO_DIR}/zen/native-messaging-hosts/pywalfox.json"
  if [[ -f "$pywalfox_src" ]]; then
    mkdir -p "${HOME}/.config/zen/native-messaging-hosts"
    safe_symlink "$pywalfox_src" "${HOME}/.config/zen/native-messaging-hosts/pywalfox.json"
  fi
}

# Ensure cloudyy helper scripts are on PATH for interactive shells
ensure_cloudyy_path() {
  log_section "Shell PATH"

  local scripts_root="${HOME}/cloudyy_scripts"
  local scripts_dir="${scripts_root}/cloudyy-other"
  if [[ -d "${scripts_root}/cloudyy_other" ]]; then
    scripts_dir="${scripts_root}/cloudyy_other"
  fi

  local rel_subdir="${scripts_dir#${HOME}/}"
  local export_root="export PATH=\"\$HOME/cloudyy_scripts:\$PATH\""
  local export_subdir="export PATH=\"\$PATH:\$HOME/${rel_subdir}\""
  local updated=0

  local -a rc_files=("${HOME}/.zshrc" "${HOME}/.bashrc")
  for rc in "${rc_files[@]}"; do
    [[ -f "$rc" ]] || touch "$rc"

    local needs_root=1 needs_subdir=1
    grep -q 'cloudyy_scripts"' "$rc" 2>/dev/null && needs_root=0
    grep -Eq 'cloudyy_scripts/(cloudyy-other|cloudyy_other)' "$rc" 2>/dev/null && needs_subdir=0

    if (( needs_root == 0 && needs_subdir == 0 )); then
      log_skip "PATH already complete in $(basename "$rc")"
      continue
    fi

    {
      printf '\n# cloudyy-linux: include helper scripts\n'
      (( needs_root ))   && printf '%s\n' "$export_root"
      (( needs_subdir )) && printf '%s\n' "$export_subdir"
    } >>"$rc"

    log_ok "Updated PATH in $(basename "$rc")"
    updated=1
  done

  if ((updated == 0)); then
    log_ok "No PATH changes needed."
  fi
}

# =============================================================================
# STEP 4.2: Shell Setup — zsh default + oh-my-zsh
# =============================================================================

setup_shell() {
  log_section "Shell Setup"

  # Set zsh as default shell if it isn't already
  local zsh_path
  zsh_path="$(command -v zsh 2>/dev/null || true)"
  if [[ -z "$zsh_path" ]]; then
    log_warn "zsh not found — skipping shell setup."
    return 0
  fi

  if [[ "$SHELL" != "$zsh_path" ]]; then
    log "Setting zsh as default shell..."
    if chsh -s "$zsh_path" 2>/dev/null; then
      log_ok "Default shell set to zsh (takes effect on next login)."
    else
      log_warn "chsh failed — run: chsh -s ${zsh_path}"
    fi
  else
    log_skip "zsh already default shell"
  fi

  # Install oh-my-zsh to ~/.config/zsh/oh-my-zsh (matches $ZSH in .zshrc)
  local omz_dir="${HOME}/.config/zsh/oh-my-zsh"
  if [[ ! -d "$omz_dir" ]]; then
    log "Installing oh-my-zsh..."
    if ZSH="$omz_dir" RUNZSH=no CHSH=no \
       sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
       "" --unattended 2>/dev/null; then
      log_ok "oh-my-zsh installed."
    else
      log_warn "oh-my-zsh install failed (non-fatal — run manually later)."
    fi
  else
    log_skip "oh-my-zsh already installed"
  fi

  # Symlink system-installed plugins into oh-my-zsh custom plugins dir
  local custom_plugins="${omz_dir}/custom/plugins"
  mkdir -p "$custom_plugins"
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    local sys_path="/usr/share/zsh/plugins/${plugin}"
    if [[ -d "$sys_path" && ! -e "${custom_plugins}/${plugin}" ]]; then
      ln -snf "$sys_path" "${custom_plugins}/${plugin}"
      log_ok "Plugin linked: ${plugin}"
    fi
  done
}

# =============================================================================
# STEP 4.5: Deploy First-Boot Defaults
# =============================================================================
# Copies distro defaults for files that are gitignored (generated at runtime).
# Only runs if the target doesn't already exist — never overwrites user files.

deploy_defaults() {
  log_section "First-Boot Defaults"

  local defaults_dir="${REPO_DIR}/install/default-theme"

  # hyprland.conf — gitignored; deploy once so Hyprland can start cleanly
  local hypr_conf="${HOME}/.config/hypr/hyprland.conf"
  if [[ ! -f "$hypr_conf" ]]; then
    if [[ -f "${defaults_dir}/hyprland.conf" ]]; then
      cp "${defaults_dir}/hyprland.conf" "$hypr_conf"
      log_ok "hyprland.conf deployed (default)."
    else
      log_warn "No default hyprland.conf in ${defaults_dir} — Hyprland may not start until configured."
    fi
  else
    log_skip "hyprland.conf"
  fi

  # matugen generated colors — gitignored; deploy so Hyprland + rofi have colors
  local generated_dir="${HOME}/.config/matugen/generated"
  mkdir -p "$generated_dir"
  local deployed=0
  for src in "${defaults_dir}/matugen/"*; do
    [[ -f "$src" ]] || continue
    local dst="${generated_dir}/$(basename "$src")"
    if [[ ! -f "$dst" ]]; then
      cp "$src" "$dst"
      (( ++deployed )) || true
    fi
  done
  if (( deployed > 0 )); then
    log_ok "${deployed} default color file(s) deployed."
  else
    log_skip "matugen generated colors"
  fi
}

# =============================================================================
# STEP 5: Post-Deployment Verification
# =============================================================================

verify_deployment() {
  log_section "Verification"

  local -a critical_links=(
    "${HOME}/.config/hypr"
    "${HOME}/.config/kitty"
  )

  local all_ok=true
  for link in "${critical_links[@]}"; do
    if [[ -e "$link" ]]; then
      log_ok "OK: ${link}"
    else
      log_warn "Missing: ${link} (dotfiles may not include this directory)"
      all_ok=false
    fi
  done

  if $all_ok; then
    log_ok "All critical config directories are present."
  fi
}

# =============================================================================
# STEP 5.5: Re-apply git skip-worktree on state files
# =============================================================================
# These flags live in the local index and are lost on a fresh clone.
# Re-applying them after every sync keeps the repo clean.

reapply_skip_worktree() {
  local -a state_files=(
    ".config/matugen/generated/colors.css"
    ".config/matugen/generated/colors-glass.rasi"
    ".config/matugen/generated/colors-swayosd.css"
    ".config/matugen/generated/gtk-3.css"
    ".config/matugen/generated/gtk-4.css"
    ".config/matugen/generated/hyprcolors.conf"
    ".config/matugen/generated/kitty-colors.conf"
    ".config/matugen/generated/matugen_colors.lua"
    ".config/matugen/generated/pywalfox-colors.json"
    ".config/matugen/generated/vscode.json"
    ".config/kitty/kitty-colors.conf"
    ".config/btop/themes/matugen.theme"
    ".config/nvim/lua/current_mode.lua"
    ".config/hypr/theme_state/state"
    ".config/hypr/theme_state/state.conf"
    ".config/hypr/theme_state/dark_last"
    ".config/hypr/theme_state/light_last"
    "cloudyy_scripts/theme_controller.sh"
    "cloudyy_scripts/bridge_scripts/bridge_default.sh"
    "cloudyy_scripts/bridge_scripts/bridge_quickshell.sh"
    ".config/hypr/theme_state/current_wallpaper/current.jpg"
    ".config/hypr/.cloud-center-state.json"
    ".config/hypr/cloudyy-launch.sh"
    ".config/quickshell/.current_preset"
    ".config/ncspot/userstate.cbor"
    ".config/waypaper/config.ini"
    ".config/btop/btop.conf"
  )
  local applied=0
  for f in "${state_files[@]}"; do
    git -C "$REPO_DIR" update-index --skip-worktree "$f" 2>/dev/null && ((++applied)) || true
  done
  log_ok "State files frozen — ${applied}/${#state_files[@]} flagged (changes won't appear in git)."
}

# =============================================================================
# STEP 6: Setup System Theme Integration
# =============================================================================

setup_system_theme() {
  log_section "System Theme Integration"

  local setup_script="${REPO_DIR}/install/setup-system-theme.sh"
  if [[ ! -f "$setup_script" ]]; then
    log_warn "Theme setup script not found: ${setup_script}"
    return 0
  fi

  if bash "$setup_script"; then
    log_ok "System theme integration configured."
  else
    log_warn "System theme setup encountered issues (non-fatal)."
  fi
}

# =============================================================================
# STEP 7: Seed Required Desktop Applications
# =============================================================================

seed_required_applications() {
  log_section "Seed Required Desktop Applications"

  local seed_script="${REPO_DIR}/install/seed-required-applications.sh"
  if [[ ! -f "$seed_script" ]]; then
    log_warn "Required app seed script not found: ${seed_script}"
    return 0
  fi

  if bash "$seed_script" "$REPO_DIR"; then
    log_ok "Required desktop applications seeded."
  else
    log_warn "Seeding required desktop applications encountered issues (non-fatal)."
  fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  # Parse flags
  for _arg in "$@"; do
    case "$_arg" in
      --unattended|-u) CLOUDYY_UNATTENDED=1 ;;
    esac
  done

  printf '\n%s%s── cloudyy-linux Dotfiles Deployment ──%s\n' "$BOLD" "$CYAN" "$RESET"
  printf 'Repo URL : %s\n' "$REPO_URL"
  printf 'Repo dir : %s\n' "$REPO_DIR"
  printf 'Backups  : %s\n\n' "$BACKUP_DIR"

  printf '%sExisting files will be backed up before being replaced.%s\n' "$YELLOW" "$RESET"
  printf 'Nothing is deleted — backups live in:\n  %s\n\n' "$BACKUP_DIR"

  if [[ "${CLOUDYY_UNATTENDED:-0}" == "1" ]]; then
    log "Unattended mode — proceeding with dotfiles deployment."
  else
    read -rp "Proceed with dotfiles deployment? [Y/n]: " _confirm
    [[ "${_confirm,,}" == "n" ]] && {
      log "Cancelled."
      exit 0
    }
  fi

  sync_repo
  reapply_skip_worktree
  link_home_dotfiles
  link_config_dirs
  link_extra_dirs
  # Only run shell setup when not orchestrated by install.sh
  # (install.sh has a dedicated phase_shell that runs after packages are installed)
  [[ "${CLOUDYY_INSTALL_ORCHESTRATED:-0}" != "1" ]] && setup_shell
  deploy_defaults
  ensure_cloudyy_path
  verify_deployment
  setup_system_theme
  seed_required_applications

  # Run schema settings (XDG portal + pywalfox) — only in standalone mode;
  # install.sh has a dedicated phase_schema for this.
  if [[ "${CLOUDYY_INSTALL_ORCHESTRATED:-0}" != "1" ]]; then
    local _schema_script
    _schema_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/schema_settings.sh"
    if [[ -f "$_schema_script" ]]; then
      bash "$_schema_script" || log_warn "schema_settings.sh encountered issues (non-fatal)"
    else
      log_warn "schema_settings.sh not found at ${_schema_script} — skipping"
    fi
  fi

  # Wire quickshell bridge and restore theme
  local _self_dir
  _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ ! -f "${_self_dir}/widget_bridge.sh" ]]; then
    log_error "widget_bridge.sh not found: ${_self_dir}/widget_bridge.sh"
    exit 1
  fi
  if [[ ! -x "${_self_dir}/widget_bridge.sh" ]]; then
    log_error "widget_bridge.sh is not executable: ${_self_dir}/widget_bridge.sh"
    exit 1
  fi
  if ! bash "${_self_dir}/widget_bridge.sh"; then
    log_error "widget_bridge.sh failed"
    exit 1
  fi

  if [[ -x "${HOME}/cloudyy_scripts/theme_controller.sh" ]]; then
    "${HOME}/cloudyy_scripts/theme_controller.sh" restore >/dev/null 2>&1 || \
      log_warn "theme_controller restore failed (non-fatal)"
  fi

  printf '\n%s[✓] Dotfiles deployed successfully!%s\n\n' "$GREEN" "$RESET"

  # Remind user to reload shell
  printf '%sTip:%s Open a new terminal or run %ssource ~/.zshrc%s to apply shell changes.\n\n' \
    "$YELLOW" "$RESET" "$BOLD" "$RESET"
}

main "$@"
