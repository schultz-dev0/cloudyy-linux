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
readonly DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

  # Strip trailing slash so ln -snf behaves consistently
  src="${src%/}"

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    log_warn "Source not found, skipping: ${src}"
    return 0
  fi

  backup_if_needed "$dst"

  # Guard: if a real (non-symlink) directory survived the backup step, ln -snf
  # would silently place the new symlink *inside* it rather than replacing it.
  if [[ -d "$dst" && ! -L "$dst" ]]; then
    log_error "Cannot symlink ${dst}: real directory still present after backup — skipping."
    return 1
  fi

  ln -snf "$src" "$dst"
  log_ok "Linked: $(basename "$dst")"
}

# Replace the last Cloudyy-owned hyprlock baseline without touching Cloud
# Center's state or managed additions. Any hand-edited baseline is left alone.
migrate_legacy_autostart() {
  local autostart_file="$1"
  local autostart_default="$2"

  [[ -f "$autostart_file" && -f "$autostart_default" ]] || return 0

  local source
  source="$(<"$autostart_file")"
  [[ "$source" != *'hl.exec_cmd("cloudyy-session-start")'* ]] || return 0
  [[ "$source" == *'hl.exec_cmd("hyprlock")'* ]] || return 0

  local state_marker='-- @cloud-center-rules-startup-state = '
  if [[ "$source" != *"${state_marker}"* ]]; then
    log_warn "Legacy autostart.lua needs a manual lockscreen migration (Cloud Center state marker missing)."
    return 0
  fi

  local legacy_prefix
  read -r -d '' legacy_prefix <<'EOF' || true
-- Autostart — equivalent of exec-once entries

hl.on("hyprland.start", function()
	local home = os.getenv("HOME")

	hl.exec_cmd("hyprlock")
	hl.exec_cmd(
		"systemctl --user start hyprpolkitagent.service 2>/dev/null || /usr/lib/hyprpolkitagent/hyprpolkitagent"
	)
	hl.exec_cmd("systemctl start geoclue.service 2>/dev/null || true")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("cloudyy-theme restore")

	hl.exec_cmd("cloudyy-system-monitor")

	hl.exec_cmd("cloudyy-quickshell-start")

	-- First-run welcome popup — skips itself once ~/.config/OOBE/.dont_show exists.
	hl.exec_cmd("test -f " .. home .. "/.config/OOBE/.dont_show || qs -n -d -p " .. home .. "/.config/OOBE")
end)
EOF

  local current_prefix="${source%%$'\n'"${state_marker}"*}"
  if [[ "$current_prefix" != "$legacy_prefix" ]]; then
    log_warn "Legacy autostart.lua has manual changes; leaving it unchanged for a manual lockscreen migration."
    return 0
  fi

  local default_source default_prefix managed_tail tmp_file
  default_source="$(<"$autostart_default")"
  default_prefix="${default_source%%$'\n'"${state_marker}"*}"
  managed_tail="${source#*"${state_marker}"}"
  tmp_file="$(mktemp "${autostart_file}.tmp.XXXXXX")"
  printf '%s\n\n%s%s\n' "$default_prefix" "$state_marker" "$managed_tail" > "$tmp_file"
  chmod --reference="$autostart_file" "$tmp_file"
  mv "$tmp_file" "$autostart_file"
  log_ok "autostart.lua migrated to the Cloudyy boot lock."
}

# =============================================================================
# STEP 1: Clone or Update Repository
# =============================================================================

sync_repo() {
  log_section "Repository"

  # If REPO_DIR exists but has no .git (e.g. failed previous clone), move it
  # aside so a clean clone can proceed.
  if [[ -e "${REPO_DIR}" && ! -d "${REPO_DIR}/.git" ]]; then
    local stale="${REPO_DIR}.stale.$(date +%s)"
    log_warn "${REPO_DIR} exists but is not a git repo — moving to ${stale}"
    mv "${REPO_DIR}" "${stale}"
  fi

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

    # Matugen is no longer Cloudyy-owned. A verified old repository link is
    # detached separately; a user-owned directory is always preserved.
    if [[ "$dirname" == "waybar" || "$dirname" == "swaync" || "$dirname" == "matugen" ]]; then
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
    mkdir -p "${REPO_DIR}/Wallpapers/user_wallpapers/Dark" \
             "${REPO_DIR}/Wallpapers/user_wallpapers/Light"
  fi

  # cloudyy_scripts — also make them executable
  if [[ -d "${REPO_DIR}/cloudyy_scripts" ]]; then
    safe_symlink "${REPO_DIR}/cloudyy_scripts" "${HOME}/cloudyy_scripts"
    find "${REPO_DIR}/cloudyy_scripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \; 2>/dev/null &&
      log_ok "cloudyy_scripts made executable." ||
      true
  fi

}

# Ensure ZDOTDIR is set so zsh reads from ~/.config/zsh/.zshrc
ensure_zdotdir() {
  log_section "ZDOTDIR"

  local zshenv="${HOME}/.zshenv"

  # Remove dangling symlink left over from when .zshenv was a tracked repo file
  if [[ -L "$zshenv" && ! -e "$zshenv" ]]; then
    log_warn ".zshenv: broken symlink detected — removing before recreating."
    rm -f "$zshenv"
  fi

  # Create as a plain file if missing
  [[ -f "$zshenv" ]] || touch "$zshenv"

  if grep -q 'ZDOTDIR' "$zshenv" 2>/dev/null; then
    log_skip "ZDOTDIR already set in .zshenv"
    return 0
  fi

  printf '\nexport ZDOTDIR="$HOME/.config/zsh"\n' >> "$zshenv"
  log_ok "ZDOTDIR set in ~/.zshenv"
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
       "" --unattended --keep-zshrc 2>/dev/null; then
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
# Seeds distro defaults for user-owned state files.
# Only runs if the target doesn't already exist — never overwrites user files.

deploy_defaults() {
  log_section "First-Boot Defaults"

  # Cloud Center terminal settings — seed defaults so .zshrc can load plugins
  # and respects show_mascot on first boot before Cloud Center runs.
  local cc_terminal_dir="${HOME}/.config/cloud-center/settings/terminal"
  mkdir -p "$cc_terminal_dir"

  local plugins_file="${cc_terminal_dir}/active_zsh_plugins.txt"
  if [[ ! -f "$plugins_file" ]]; then
    printf 'zsh-autosuggestions\nzsh-syntax-highlighting\n' > "$plugins_file"
    log_ok "Default zsh plugins seeded (zsh-autosuggestions, zsh-syntax-highlighting)."
  else
    log_skip "active_zsh_plugins.txt"
  fi

  local mascot_file="${cc_terminal_dir}/show_mascot"
  if [[ ! -f "$mascot_file" ]]; then
    printf 'false\n' > "$mascot_file"
    log_ok "show_mascot default seeded."
  else
    log_skip "show_mascot"
  fi

  # .zshrc — never tracked in git (it's personal, edited live); seed once
  # from the generic default, then leave it alone forever.
  local zshrc="${HOME}/.config/zsh/.zshrc"
  local zshrc_default="${REPO_DIR}/install/assets/defaults/.zshrc"
  if [[ ! -f "$zshrc" ]]; then
    if [[ -f "$zshrc_default" ]]; then
      mkdir -p "$(dirname "$zshrc")"
      cp "$zshrc_default" "$zshrc"
      log_ok ".zshrc deployed (default)."
    else
      log_warn "No default .zshrc in install/assets/defaults/."
    fi
  else
    log_skip ".zshrc"
  fi

  # Hyprland Lua entry point — never tracked in git; its require lines are
  # static and never rewritten at runtime. Seed once from the generic
  # preset, then leave it alone forever.
  local hypr_defaults_dir="${REPO_DIR}/install/assets/defaults/hypr"
  local hypridle_conf="${HOME}/.config/hypr/hypridle.conf"
  local hypridle_default="${hypr_defaults_dir}/hypridle.conf"
  if [[ ! -f "$hypridle_conf" && -f "$hypridle_default" ]]; then
    mkdir -p "$(dirname "$hypridle_conf")"
    cp "$hypridle_default" "$hypridle_conf"
    log_ok "hypridle.conf deployed (default)."
  elif [[ -f "$hypridle_conf" ]]; then
    log_skip "hypridle.conf"
  fi

  local hyprland_lua="${HOME}/.config/hypr/hyprland.lua"
  local hyprland_lua_default="${hypr_defaults_dir}/hyprland.lua"
  if [[ ! -f "$hyprland_lua" ]]; then
    if [[ -f "$hyprland_lua_default" ]]; then
      mkdir -p "$(dirname "$hyprland_lua")"
      cp "$hyprland_lua_default" "$hyprland_lua"
      log_ok "hyprland.lua deployed (default)."
    else
      log_warn "No default hyprland.lua in ${hypr_defaults_dir} — Hyprland will not start until configured."
    fi
  else
    log_skip "hyprland.lua"
  fi

  # Hyprland config modules — one file per module, never tracked in git;
  # Cloud Center edits each one in place. Seed once, then leave alone.
  local hypr_modules=(
    bindings lookandfeel animations input cursor
    monitors autostart windowrules variables colors
  )
  migrate_legacy_autostart \
    "${HOME}/.config/hypr/autostart.lua" \
    "${hypr_defaults_dir}/autostart.lua"

  local module_deployed=0
  for module in "${hypr_modules[@]}"; do
    local module_file="${HOME}/.config/hypr/${module}.lua"
    local module_default="${hypr_defaults_dir}/${module}.lua"
    if [[ ! -f "$module_file" ]]; then
      if [[ -f "$module_default" ]]; then
        mkdir -p "$(dirname "$module_file")"
        cp "$module_default" "$module_file"
        (( ++module_deployed )) || true
      else
        log_warn "No default ${module}.lua in ${hypr_defaults_dir}."
      fi
    fi
  done
  if (( module_deployed > 0 )); then
    log_ok "${module_deployed} Hyprland config module(s) deployed (incl. bindings, lookandfeel, animations)."
  else
    log_skip "Hyprland config modules"
  fi

  # Audio auto-switch systemd unit — gitignored; setup-audio-autoswitch.sh
  # expects it already deployed and only enables/disables it.
  local audio_unit="${HOME}/.config/systemd/user/cloudyy-audio-autoswitch.service"
  local audio_unit_default="${defaults_dir}/systemd/cloudyy-audio-autoswitch.service"
  if [[ -f "$audio_unit_default" ]]; then
    mkdir -p "$(dirname "$audio_unit")"
    if [[ ! -f "$audio_unit" ]] || ! cmp -s "$audio_unit_default" "$audio_unit"; then
      cp "$audio_unit_default" "$audio_unit"
      log_ok "cloudyy-audio-autoswitch.service deployed."
    else
      log_skip "cloudyy-audio-autoswitch.service"
    fi
  else
    log_warn "No default cloudyy-audio-autoswitch.service in ${defaults_dir}/systemd."
  fi

  local cwd_walk_file="${cc_terminal_dir}/cwd_walk"
  if [[ ! -f "$cwd_walk_file" ]]; then
    printf 'true\n' > "$cwd_walk_file"
    log_ok "cwd_walk default seeded."
  else
    log_skip "cwd_walk"
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
# PRE-FLIGHT: Conflict scan
# =============================================================================
# Enumerate every destination that safe_symlink will touch. Report anything
# that already exists on disk and isn't already our own symlink, so the user
# can see exactly what will be backed up before a single file is moved.

_is_our_link() {
  local p="$1"
  [[ -L "$p" ]] || return 1
  local t
  t="$(readlink -f "$p" 2>/dev/null)" || return 1
  [[ "$t" == "${REPO_DIR}"* ]]
}

preflight_conflicts() {
  log_section "Pre-flight Conflict Scan"
  local -a conflicts=()

  # Home dotfiles
  while IFS= read -r -d '' dotfile; do
    local dst="${HOME}/$(basename "$dotfile")"
    [[ -e "$dst" || -L "$dst" ]] || continue
    _is_our_link "$dst" && continue
    local kind="file"
    [[ -d "$dst" ]] && kind="dir"
    [[ -L "$dst" ]] && kind="symlink→$(readlink "$dst" 2>/dev/null)"
    conflicts+=("~/${dst#${HOME}/}  [${kind}]")
  done < <(find "$REPO_DIR" -maxdepth 1 \
    -name ".*" \
    ! -name ".config" \
    ! -name ".git" \
    ! -name ".gitignore" \
    ! -name ".gitmodules" \
    ! -name ".local" \
    -print0 2>/dev/null)

  # .config directories
  local config_src="${REPO_DIR}/.config"
  if [[ -d "$config_src" ]]; then
    for dir in "${config_src}"/*/; do
      [[ -d "$dir" ]] || continue
      local dirname
      dirname="$(basename "$dir")"
      [[ "$dirname" == "waybar" || "$dirname" == "swaync" || "$dirname" == "matugen" ]] && continue
      local dst="${HOME}/.config/${dirname}"
      [[ -e "$dst" || -L "$dst" ]] || continue
      _is_our_link "$dst" && continue
      local kind="dir"
      [[ -L "$dst" ]] && kind="symlink→$(readlink "$dst" 2>/dev/null)"
      conflicts+=("~/.config/${dirname}  [${kind}]")
    done
  fi

  # Extra top-level dirs (Wallpapers, cloudyy_scripts)
  for pair in "Wallpapers:${HOME}/Wallpapers" "cloudyy_scripts:${HOME}/cloudyy_scripts"; do
    local src_name="${pair%%:*}" dst="${pair##*:}"
    [[ -d "${REPO_DIR}/${src_name}" ]] || continue
    [[ -e "$dst" || -L "$dst" ]] || continue
    _is_our_link "$dst" && continue
    local kind="dir"
    [[ -L "$dst" ]] && kind="symlink→$(readlink "$dst" 2>/dev/null)"
    conflicts+=("~/${src_name}  [${kind}]")
  done

  if (( ${#conflicts[@]} == 0 )); then
    log_ok "No conflicts found — clean deployment."
    return 0
  fi

  log_warn "${#conflicts[@]} existing path(s) will be backed up before being replaced:"
  for c in "${conflicts[@]}"; do
    log_warn "  · ${c}"
  done
  log_warn "Backup destination: ${BACKUP_DIR}"
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

  bash "${DEPLOY_SCRIPT_DIR}/retire-legacy-matugen-link.sh" "$REPO_DIR" "$BACKUP_DIR"
  sync_repo
  reapply_skip_worktree
  preflight_conflicts
  link_home_dotfiles
  link_config_dirs
  link_extra_dirs
  # Only run shell setup when not orchestrated by install.sh
  # (install.sh has a dedicated phase_shell that runs after packages are installed)
  [[ "${CLOUDYY_INSTALL_ORCHESTRATED:-0}" != "1" ]] && setup_shell
  deploy_defaults
  ensure_zdotdir
  verify_deployment
  # Run schema settings (XDG portal) — only in standalone mode;
  # install.sh has a dedicated phase_schema for this.
  if [[ "${CLOUDYY_INSTALL_ORCHESTRATED:-0}" != "1" ]]; then
    local _schema_script
    _schema_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/schema.sh"
    if [[ -f "$_schema_script" ]]; then
      bash "$_schema_script" || log_warn "schema_settings.sh encountered issues (non-fatal)"
    else
      log_warn "schema_settings.sh not found at ${_schema_script} — skipping"
    fi

  fi

  # Skip when orchestrated by install.sh: its dedicated theme_init phase runs
  # after packages are installed. Standalone deployment performs the same
  # headless bootstrap without contacting the graphical session.
  if [[ "${CLOUDYY_INSTALL_ORCHESTRATED:-0}" != "1" ]]; then
    if command -v cloudyy-theme >/dev/null 2>&1; then
      cloudyy-theme bootstrap nord >/dev/null 2>&1 || \
        log_warn "cloudyy-theme bootstrap nord failed (non-fatal)"
    fi
  fi

  printf '\n%s[✓] Dotfiles deployed successfully!%s\n\n' "$GREEN" "$RESET"

  # Remind user to reload shell
  printf '%sTip:%s Open a new terminal or run %ssource ~/.zshrc%s to apply shell changes.\n\n' \
    "$YELLOW" "$RESET" "$BOLD" "$RESET"
}

main "$@"
