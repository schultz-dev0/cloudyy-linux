#!/usr/bin/env bash
# =============================================================================
# cwd_spawn.sh — Context-Aware Directory Spawner
# Opens kitty or thunar in the working directory of the currently focused window
#
# Usage:
#   cwd_spawn.sh term       — open kitty in focused window's CWD
#   cwd_spawn.sh files      — open thunar in focused window's CWD
#   cwd_spawn.sh yazi       — open yazi (TUI) in focused window's CWD
#
# Bind each mode to a separate keybind in hyprland.conf, e.g:
#   bind = $mod, Return,    exec, ~/cloudyy_scripts/cwd_spawn.sh term
#   bind = $mod SHIFT, E,   exec, ~/cloudyy_scripts/cwd_spawn.sh files
# =============================================================================

set -uo pipefail

# =============================================================================
# CONFIG
# =============================================================================

readonly TERMINAL="kitty"
readonly FILE_MANAGER_GUI="thunar"
readonly FILE_MANAGER_TUI="yazi"
readonly FALLBACK_DIR="${HOME}"

# Terminal class names — used to do a deeper CWD lookup via child shell PID
# (when a terminal is focused, hyprctl gives us the terminal's PID, not the
#  shell's — so we need to walk down to the foreground child process)
readonly -a KNOWN_TERMINALS=(
  kitty
  alacritty
  foot
  wezterm
  ghostty
  konsole
  gnome-terminal
  xterm
)

# =============================================================================
# LOGGING  (goes to stderr so it never pollutes command substitutions)
# =============================================================================

log() { echo "[cwd_spawn] $*" >&2; }
warn() { echo "[cwd_spawn] WARN: $*" >&2; }

# =============================================================================
# STEP 1 — GET FOCUSED WINDOW INFO
# =============================================================================

get_active_window_json() {
  hyprctl activewindow -j 2>/dev/null
}

get_active_pid() {
  local json="$1"
  echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
pid = data.get('pid', 0)
print(pid if pid > 0 else '')
" 2>/dev/null
}

get_active_title() {
  local json="$1"
  echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('title', ''))
" 2>/dev/null
}

get_active_class() {
  local json="$1"
  echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('class', '').lower())
" 2>/dev/null
}

# GUI file managers — these need title+fd resolution, not /proc/cwd
readonly -a KNOWN_FILE_MANAGERS=(
  thunar
  nautilus
  nemo
  dolphin
  pcmanfm
  caja
  ranger # TUI but same issue
)

# =============================================================================
# STEP 2 — RESOLVE THE REAL WORKING DIRECTORY
# =============================================================================

# Read a PID's cwd from /proc (returns empty string on failure)
read_proc_cwd() {
  local pid="$1"
  [[ -z "$pid" || ! -d "/proc/$pid" ]] && return 0
  readlink "/proc/${pid}/cwd" 2>/dev/null || true
}

# Check whether a process name matches any of our known terminals
is_terminal_class() {
  local class="$1"
  for t in "${KNOWN_TERMINALS[@]}"; do
    [[ "$class" == *"$t"* ]] && return 0
  done
  return 1
}

# Check whether a process is a GUI file manager
is_file_manager_class() {
  local class="$1"
  for fm in "${KNOWN_FILE_MANAGERS[@]}"; do
    [[ "$class" == *"$fm"* ]] && return 0
  done
  return 1
}

# GUI file managers don't update kernel CWD while navigating.
# Strategy: extract current folder name from window title, then scan
# /proc/[PID]/fd/ for an open directory FD whose basename matches.
resolve_file_manager_cwd() {
  local pid="$1"
  local title="$2"

  # Thunar:   "projects — Thunar"  or  "Home"
  # Nautilus: "projects"
  # Nemo:     "projects"
  # Strip known suffixes to get the bare folder name
  local folder_hint
  folder_hint=$(echo "$title" |
    sed -E 's/ [—–-] Thunar$//I' |
    sed -E 's/ [—–-] Files$//I' |
    sed -E 's/ [—–-] File Manager$//I' |
    xargs)

  log "File manager title hint: '${folder_hint}'"

  # "Home" is a special label Thunar uses for $HOME
  if [[ "$folder_hint" == "Home" || "$folder_hint" == "$(basename "$HOME")" ]]; then
    echo "$HOME"
    return
  fi

  # Walk every open file descriptor looking for a directory whose name matches
  local fd_dir="/proc/${pid}/fd"
  if [[ -d "$fd_dir" ]]; then
    # Sort by fd number descending — most recently opened FDs tend to be higher
    while IFS= read -r fd_link; do
      local target
      target=$(readlink "$fd_link" 2>/dev/null) || continue
      [[ -d "$target" ]] || continue         # skip non-directories
      [[ "$target" == /proc/* ]] && continue # skip procfs noise
      [[ "$target" == /sys/* ]] && continue  # skip sysfs noise

      if [[ "$(basename "$target")" == "$folder_hint" ]]; then
        log "Matched FD path: $target"
        echo "$target"
        return
      fi
    done < <(ls -v "$fd_dir" 2>/dev/null | sort -rn | sed "s|^|${fd_dir}/|")
  fi

  # Second pass: if the hint looks like an absolute path fragment, try it directly
  if [[ -d "$folder_hint" ]]; then
    echo "$folder_hint"
    return
  fi

  # Last resort: kernel CWD (will usually be $HOME or launch dir)
  warn "FD scan found no match for '${folder_hint}', falling back to proc CWD"
  read_proc_cwd "$pid"
}

# For terminal emulators, hyprctl gives us the terminal's PID — but we want
# the shell/program running *inside* it. We walk the process tree looking for
# the foreground child with its own distinct CWD.
resolve_terminal_cwd() {
  local term_pid="$1"

  # List every child PID of the terminal process
  local children
  children=$(pgrep -P "$term_pid" 2>/dev/null || true)

  [[ -z "$children" ]] && {
    # No children found — fall back to the terminal's own CWD
    read_proc_cwd "$term_pid"
    return
  }

  # Walk children; prefer the one with the deepest/most-specific path
  local best_cwd=""
  local best_depth=0

  while IFS= read -r child_pid; do
    [[ -z "$child_pid" ]] && continue

    local child_cwd
    child_cwd=$(read_proc_cwd "$child_pid")
    [[ -z "$child_cwd" ]] && continue

    # Skip kernel threads and proc paths that aren't real dirs
    [[ ! -d "$child_cwd" ]] && continue

    # Prefer paths that look like real user directories (not /)
    local depth
    depth=$(echo "$child_cwd" | tr -cd '/' | wc -c)

    if ((depth > best_depth)); then
      best_depth="$depth"
      best_cwd="$child_cwd"
    fi
  done <<<"$children"

  # If still empty, recurse one level deeper (handles shell → editor chains)
  if [[ -z "$best_cwd" ]]; then
    local first_child
    first_child=$(pgrep -P "$term_pid" 2>/dev/null | head -1 || true)
    [[ -n "$first_child" ]] && best_cwd=$(resolve_terminal_cwd "$first_child")
  fi

  echo "${best_cwd:-$(read_proc_cwd "$term_pid")}"
}

resolve_cwd() {
  local pid="$1"
  local class="$2"
  local title="$3"

  local cwd=""

  if is_file_manager_class "$class"; then
    log "Focused window is a file manager (${class}), using title+fd resolution..."
    cwd=$(resolve_file_manager_cwd "$pid" "$title")
  elif is_terminal_class "$class"; then
    log "Focused window is a terminal (${class}), walking child processes..."
    cwd=$(resolve_terminal_cwd "$pid")
  else
    log "Focused window is ${class}, reading /proc/${pid}/cwd directly"
    cwd=$(read_proc_cwd "$pid")
  fi

  # Validate the result is an accessible directory
  if [[ -n "$cwd" && -d "$cwd" ]]; then
    echo "$cwd"
  else
    warn "Could not resolve CWD (got: '${cwd:-empty}'), using fallback: $FALLBACK_DIR"
    echo "$FALLBACK_DIR"
  fi
}

# =============================================================================
# STEP 3 — LAUNCH THE TARGET APP
# =============================================================================

spawn_terminal() {
  local dir="$1"
  log "Spawning kitty in: $dir"
  uwsm-app -- "$TERMINAL" --directory "$dir" >/dev/null 2>&1 &
  disown
}

spawn_files_gui() {
  local dir="$1"
  log "Spawning thunar in: $dir"
  uwsm-app -- "$FILE_MANAGER_GUI" "$dir" >/dev/null 2>&1 &
  disown
}

spawn_files_tui() {
  local dir="$1"
  log "Spawning yazi in: $dir"
  uwsm-app -- "$TERMINAL" --directory "$dir" \
    --class "yazi_spawned" \
    -e "$FILE_MANAGER_TUI" "$dir" >/dev/null 2>&1 &
  disown
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  local mode="${1:-term}"

  # Validate mode early
  case "$mode" in
  term | files | yazi) ;;
  *)
    warn "Unknown mode '${mode}'. Valid modes: term, files, yazi"
    exit 1
    ;;
  esac

  # 1. Get focused window info
  local win_json
  win_json=$(get_active_window_json)

  if [[ -z "$win_json" || "$win_json" == "null" || "$win_json" == "{}" ]]; then
    warn "No active window detected (is Hyprland running?). Using fallback dir."
    local target_dir="$FALLBACK_DIR"
  else
    # 2. Extract PID and class
    local pid class title
    pid=$(get_active_pid "$win_json")
    class=$(get_active_class "$win_json")
    title=$(get_active_title "$win_json")

    log "Active window — class: '${class}', title: '${title}', PID: '${pid}'"

    if [[ -z "$pid" ]]; then
      warn "Could not extract PID. Using fallback dir."
      local target_dir="$FALLBACK_DIR"
    else
      # 3. Resolve the real CWD
      local target_dir
      target_dir=$(resolve_cwd "$pid" "$class" "$title")
    fi
  fi

  log "Target directory: $target_dir"

  # 4. Launch
  case "$mode" in
  term) spawn_terminal "$target_dir" ;;
  files) spawn_files_gui "$target_dir" ;;
  yazi) spawn_files_tui "$target_dir" ;;
  esac
}

main "$@"
