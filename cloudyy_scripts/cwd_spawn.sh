#!/usr/bin/env bash
# =============================================================================
# cwd_spawn.sh — Context-Aware Directory Spawner
#
# KITTY REQUIREMENT — add these two lines to kitty.conf:
#   allow_remote_control yes
#   listen_on unix:/tmp/kitty-{kitty_pid}
#
# THUNAR REQUIREMENT — force full path in title for O(1) resolution:
#   xfconf-query --channel thunar --property /misc-window-title-style --create --type string --set THUNAR_WINDOW_TITLE_STYLE_FULL_PATH_WITH_THUNAR_SUFFIX
#
# DEPENDENCIES: jq, fd (optional but recommended), psmisc (for pstree), sqlite3
# =============================================================================

set -uo pipefail

readonly TERMINAL="kitty"
readonly FILE_MANAGER_GUI="thunar"
readonly FILE_MANAGER_TUI="yazi"
readonly FALLBACK_DIR="${HOME}"
readonly LOG_FILE="/tmp/cwd_spawn.log"
readonly DEBUG="${DEBUG:-0}"

readonly -a KNOWN_TERMINALS=(
  kitty alacritty foot wezterm ghostty konsole gnome-terminal xterm
)
readonly -a KNOWN_FILE_MANAGERS=(
  thunar nautilus nemo dolphin pcmanfm caja
)
readonly -a KNOWN_CODE_EDITORS=(
  codium vscodium code vscode
)
readonly -a KNOWN_SHELLS=(
  bash zsh fish sh dash ksh tcsh
)
readonly -a IGNORED_PROCS=(
  kitten kitty ".kitty-wrapped" login sshd
)

# =============================================================================
# LOGGING
# =============================================================================

log() { [[ "$DEBUG" == "1" ]] && echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2 || true; }
warn() { echo "[cwd_spawn] WARN: $*" >&2; }

# =============================================================================
# HYPRCTL (jq optimized)
# =============================================================================

get_active_window_info() {
  hyprctl activewindow -j 2>/dev/null | jq -r -e 'if . == {} then "||" else "\(.pid)|\(.class | ascii_downcase)|\(.title)" end' || echo "||"
}

get_recent_file_manager_info() {
  hyprctl clients -j 2>/dev/null | jq -r -e '
        map(select(.class | ascii_downcase | test("thunar|nautilus|nemo|dolphin|pcmanfm|caja")))
        | sort_by(.focusHistoryID)
        | .[0]
        | if . == null then "||" else "\(.pid)|\(.class | ascii_downcase)|\(.title)" end
    ' || echo "||"
}

# =============================================================================
# PROC HELPERS
# =============================================================================

read_proc_cwd() { [[ -d "/proc/$1" ]] && readlink "/proc/$1/cwd" 2>/dev/null || true; }
read_proc_comm() { local _c; { IFS= read -r _c < "/proc/$1/comm"; } 2>/dev/null; printf '%s' "${_c:-}"; }

read_proc_env_var() {
  [[ -r "/proc/$1/environ" ]] || return 0
  grep -z -m1 "^${2}=" "/proc/$1/environ" 2>/dev/null | cut -z -d= -f2- | tr -d '\0'
}

is_shell() {
  local comm="$1"
  for sh in "${KNOWN_SHELLS[@]}"; do [[ "$comm" == "$sh" || "$comm" == "-$sh" ]] && return 0; done
  return 1
}

is_code_editor_class() {
  for e in "${KNOWN_CODE_EDITORS[@]}"; do [[ "$1" == *"$e"* ]] && return 0; done
  return 1
}

is_ignored_proc() {
  for p in "${IGNORED_PROCS[@]}"; do [[ "$1" == "$p" ]] && return 0; done
  return 1
}

is_terminal_class() {
  for t in "${KNOWN_TERMINALS[@]}"; do [[ "$1" == *"$t"* ]] && return 0; done
  return 1
}

is_file_manager_class() {
  for fm in "${KNOWN_FILE_MANAGERS[@]}"; do [[ "$1" == *"$fm"* ]] && return 0; done
  return 1
}

get_all_descendants() {
  # Replaces slow bash recursion with a single fast C-compiled call
  pstree -p "$1" 2>/dev/null | grep -oP '\(\K[0-9]+(?=\))' | grep -v "^$1$" || true
}

# =============================================================================
# KITTY RESOLUTION
# =============================================================================

find_kitty_socket() {
  local kitty_pid="$1"
  local sock

  sock=$(read_proc_env_var "$kitty_pid" "KITTY_LISTEN_ON")
  if [[ -n "$sock" ]]; then
    echo "$sock"
    return
  fi

  for child in $(get_all_descendants "$kitty_pid" | head -20); do
    sock=$(read_proc_env_var "$child" "KITTY_LISTEN_ON" 2>/dev/null)
    if [[ -n "$sock" ]]; then
      echo "$sock"
      return
    fi
  done

  local -a all_sockets=()
  while IFS= read -r line; do
    local path="${line##* }"
    [[ "$path" == /* && -S "$path" ]] && all_sockets+=("$path")
  done </proc/net/unix 2>/dev/null

  local fd_dir="/proc/${kitty_pid}/fd"
  if [[ -d "$fd_dir" ]]; then
    local fd_entry resolved sock_path
    for fd_entry in "$fd_dir"/*; do
      [[ -L "$fd_entry" ]] || continue
      resolved=$(readlink "$fd_entry" 2>/dev/null) || continue
      for sock_path in "${all_sockets[@]}"; do
        if [[ "$resolved" == "$sock_path" ]]; then
          echo "unix:$sock_path"
          return
        fi
      done
    done
  fi
  echo ""
}

kitty_api_cwd() {
  timeout 2s kitty @ --to "$1" ls 2>/dev/null | jq -r '.[].tabs[]? | select(.is_focused==true) | .windows[]? | select(.is_focused==true) | .cwd' | head -1 || true
}

kitty_windowid_cwd() {
  local kitty_pid="$1"
  local -a descendants
  mapfile -t descendants < <(get_all_descendants "$kitty_pid")

  declare -A wid_shell_cwd wid_nonshell_cwd
  for pid in "${descendants[@]}"; do
    [[ -d "/proc/$pid" ]] || continue
    local cwd comm wid
    cwd=$(read_proc_cwd "$pid")
    [[ -z "$cwd" || ! -d "$cwd" ]] && continue
    comm=$(read_proc_comm "$pid")

    is_ignored_proc "$comm" && continue

    wid=$(read_proc_env_var "$pid" "KITTY_WINDOW_ID")
    [[ -z "$wid" ]] && continue

    local _dt="${cwd//[^\/]/}"
    local depth=${#_dt}

    if is_shell "$comm"; then
      local existing="${wid_shell_cwd[$wid]:-}"
      local existing_depth=0
      if [[ -n "$existing" ]]; then local _de="${existing//[^\/]/}"; existing_depth=${#_de}; fi
      if [[ -z "$existing" || $depth -gt $existing_depth ]]; then
        wid_shell_cwd[$wid]="$cwd"
      fi
    else
      local existing="${wid_nonshell_cwd[$wid]:-}"
      local existing_depth=0
      if [[ -n "$existing" ]]; then local _de="${existing//[^\/]/}"; existing_depth=${#_de}; fi
      if [[ -z "$existing" || $depth -gt $existing_depth ]]; then
        wid_nonshell_cwd[$wid]="$cwd"
      fi
    fi
  done

  declare -A wid_to_cwd
  for wid in "${!wid_shell_cwd[@]}"; do
    local sc="${wid_shell_cwd[$wid]:-}"
    local nc="${wid_nonshell_cwd[$wid]:-}"
    local sc_depth=0 nc_depth=0
    if [[ -n "$sc" ]]; then local _ds="${sc//[^\/]/}"; sc_depth=${#_ds}; fi
    if [[ -n "$nc" ]]; then local _dn="${nc//[^\/]/}"; nc_depth=${#_dn}; fi
    if [[ -n "$nc" && $nc_depth -ge $sc_depth ]]; then
      wid_to_cwd[$wid]="$nc"
    else
      wid_to_cwd[$wid]="$sc"
    fi
  done
  for wid in "${!wid_nonshell_cwd[@]}"; do
    [[ -z "${wid_to_cwd[$wid]:-}" ]] && wid_to_cwd[$wid]="${wid_nonshell_cwd[$wid]}"
  done

  if [[ ${#wid_to_cwd[@]} -eq 0 ]]; then
    echo ""
    return
  fi
  if [[ ${#wid_to_cwd[@]} -eq 1 ]]; then
    echo "${wid_to_cwd[*]}"
    return
  fi

  local best=""
  for wid in "${!wid_to_cwd[@]}"; do
    local c="${wid_to_cwd[$wid]}"
    if [[ "$c" != "$HOME" ]]; then
      best="$c"
      break
    fi
  done
  echo "${best:-${wid_to_cwd[*]% *}}"
}

resolve_kitty_cwd() {
  local kitty_pid="$1"
  local socket api_cwd wid_cwd

  socket=$(find_kitty_socket "$kitty_pid")
  if [[ -n "$socket" ]]; then
    api_cwd=$(kitty_api_cwd "$socket")
    if [[ -n "$api_cwd" && -d "$api_cwd" ]]; then
      echo "$api_cwd"
      return
    fi
  fi

  wid_cwd=$(kitty_windowid_cwd "$kitty_pid")
  if [[ -n "$wid_cwd" && -d "$wid_cwd" ]]; then
    echo "$wid_cwd"
    return
  fi

  resolve_terminal_cwd_generic "$kitty_pid"
}

# =============================================================================
# GENERIC TERMINAL TREE WALK
# =============================================================================

resolve_terminal_cwd_generic() {
  local term_pid="$1"
  local -a descendants
  mapfile -t descendants < <(get_all_descendants "$term_pid")

  local best_non_shell="" best_shell="" best_any=""
  local best_non_shell_depth=0 best_shell_depth=0

  for pid in "${descendants[@]}"; do
    [[ -d "/proc/$pid" ]] || continue
    local cwd comm
    cwd=$(read_proc_cwd "$pid")
    [[ -z "$cwd" || ! -d "$cwd" || "$cwd" == "/" ]] && continue
    comm=$(read_proc_comm "$pid")

    is_ignored_proc "$comm" && continue

    local _dt="${cwd//[^\/]/}"
    local depth=${#_dt}

    if is_shell "$comm"; then
      if [[ -z "$best_shell" || $depth -gt $best_shell_depth ]]; then
        best_shell="$cwd"
        best_shell_depth=$depth
      fi
    else
      if [[ -z "$best_non_shell" || $depth -gt $best_non_shell_depth ]]; then
        best_non_shell="$cwd"
        best_non_shell_depth=$depth
      fi
    fi
    [[ -z "$best_any" ]] && best_any="$cwd"
  done

  local result
  if [[ -n "$best_non_shell" && $best_non_shell_depth -ge $best_shell_depth ]]; then
    result="$best_non_shell"
  else
    result="${best_shell:-${best_non_shell:-${best_any:-}}}"
  fi

  if [[ -n "$result" && -d "$result" ]]; then
    echo "$result"
  else
    read_proc_cwd "$term_pid"
  fi
}

# =============================================================================
# FILE MANAGER (Title Parse -> XDG -> fd/find fallback)
# =============================================================================

resolve_file_manager_cwd() {
  local pid="$1" title="$2"

  # Strip known file-manager window title suffixes — pure bash, no forks
  local folder_hint="$title"
  folder_hint="${folder_hint% — Thunar}"
  folder_hint="${folder_hint% - Thunar}"
  folder_hint="${folder_hint% — Files}"
  folder_hint="${folder_hint% - Files}"
  folder_hint="${folder_hint% — File Manager}"
  folder_hint="${folder_hint% - File Manager}"

  log "File manager hint: '${folder_hint}'"
  [[ -z "$folder_hint" ]] && {
    echo "$HOME"
    return
  }

  # 1. Direct path check (O(1) fast resolve for configured Thunar)
  if [[ "$folder_hint" == /* && -d "$folder_hint" ]]; then
    log "Absolute path found: $folder_hint"
    echo "$folder_hint"
    return
  elif [[ "$folder_hint" == ~* ]]; then
    local expanded="${folder_hint/#\~/$HOME}"
    if [[ -d "$expanded" ]]; then
      log "Tilde path found: $expanded"
      echo "$expanded"
      return
    fi
  fi

  # 2. XDG standard dirs check
  declare -A xdg_dirs=(
    ["Home"]="$HOME"
    ["$(basename "$HOME")"]="$HOME"
    ["Downloads"]="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
    ["Documents"]="${XDG_DOCUMENTS_DIR:-$HOME/Documents}"
    ["Pictures"]="${XDG_PICTURES_DIR:-$HOME/Pictures}"
    ["Music"]="${XDG_MUSIC_DIR:-$HOME/Music}"
    ["Videos"]="${XDG_VIDEOS_DIR:-$HOME/Videos}"
    ["Desktop"]="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  )
  if [[ -n "${xdg_dirs[$folder_hint]:-}" && -d "${xdg_dirs[$folder_hint]}" ]]; then
    log "XDG match: ${xdg_dirs[$folder_hint]}"
    echo "${xdg_dirs[$folder_hint]}"
    return
  fi

  # 3. Open file-descriptor scan — free try; works if Thunar still has the dir open.
  log "Scanning open FDs for: '${folder_hint}'"
  local fd_dir_result
  while IFS= read -r fd_target; do
    [[ "$fd_target" == "$HOME"* ]] || continue
    [[ "$(basename "$fd_target")" == "$folder_hint" ]] || continue
    fd_dir_result="$fd_target"
    break
  done < <(find "/proc/$pid/fd" -maxdepth 1 -xtype d -printf "%l\n" 2>/dev/null)
  if [[ -n "$fd_dir_result" && -d "$fd_dir_result" ]]; then
    log "FD scan match: $fd_dir_result"
    echo "$fd_dir_result"
    return
  fi

  # We are in the slow fallback path, which means Thunar is NOT showing full paths in
  # its title. Auto-apply the full-path title style so all future spawns are O(1).
  # Thunar picks up xfconf changes live — no restart needed.
  if command -v xfconf-query >/dev/null 2>&1; then
    xfconf-query --channel thunar --property /misc-window-title-style \
      --create --type string \
      --set "THUNAR_WINDOW_TITLE_STYLE_FULL_PATH_WITH_THUNAR_SUFFIX" 2>/dev/null \
      && log "Auto-applied Thunar full-path title style (future spawns will be O(1))"
  fi

  # 4. Filesystem search fallback (capped depth + timeout to prevent multi-second hangs)
  log "Searching \$HOME for: '${folder_hint}'"
  local best
  if command -v fd >/dev/null 2>&1; then
    best=$(timeout 1s fd --max-depth 5 --max-results 1 --type d --hidden false "^${folder_hint}$" "$HOME" 2>/dev/null | head -1)
  else
    best=$(timeout 1s find "$HOME" -maxdepth 4 -type d -name "$folder_hint" ! -path "*/.*" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d" " -f2-)
  fi

  if [[ -n "$best" && -d "$best" ]]; then
    echo "$best"
    return
  fi

  warn "Could not resolve '${folder_hint}' — using HOME"
  echo "$HOME"
}

# =============================================================================
# DISPATCH
# =============================================================================

resolve_cwd() {
  local pid="$1" class="$2" title="$3"
  local cwd=""

  if [[ "$class" == *"kitty"* ]]; then
    cwd=$(resolve_kitty_cwd "$pid")
  elif is_code_editor_class "$class"; then
    cwd=$(resolve_vscodium_cwd "$title")
  elif is_file_manager_class "$class"; then
    cwd=$(resolve_file_manager_cwd "$pid" "$title")
  elif is_terminal_class "$class"; then
    cwd=$(resolve_terminal_cwd_generic "$pid")
  else
    cwd=$(read_proc_cwd "$pid")
  fi

  if [[ -n "$cwd" && -d "$cwd" ]]; then
    echo "$cwd"
  else
    warn "Resolution failed — using $FALLBACK_DIR"
    echo "$FALLBACK_DIR"
  fi
}

# =============================================================================
# LAUNCH
# =============================================================================

spawn_terminal() {
  uwsm-app -- "$TERMINAL" --directory "$1" >/dev/null 2>&1 &
  disown
}
spawn_files_gui() {
  uwsm-app -- "$FILE_MANAGER_GUI" "$1" >/dev/null 2>&1 &
  disown
}
spawn_files_tui() {
  uwsm-app -- "$TERMINAL" --directory "$1" --class "yazi_spawned" -e "$FILE_MANAGER_TUI" "$1" >/dev/null 2>&1 &
  disown
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  local mode="${1:-term}"
  case "$mode" in
  term | files | yazi) ;;
  *)
    warn "Unknown mode '${mode}'. Valid: term, files, yazi"
    exit 1
    ;;
  esac

  [[ "$DEBUG" == "1" ]] && : >"$LOG_FILE"
  log "=== cwd_spawn mode=$mode ==="

  local info pid class title
  info=$(get_active_window_info)
  IFS='|' read -r pid class title <<<"$info"

  # Fix for terminal-triggered tests stealing focus:
  # If we want a file manager but a terminal is currently active,
  # check if a file manager was recently used in the background.
  if [[ "$mode" == "files" || "$mode" == "yazi" ]] && is_terminal_class "$class"; then
    log "Terminal active. Searching background file managers..."
    local fm_info fm_pid fm_class fm_title
    fm_info=$(get_recent_file_manager_info)
    IFS='|' read -r fm_pid fm_class fm_title <<<"$fm_info"

    if [[ -n "$fm_pid" && "$fm_pid" != "||" ]]; then
      pid="$fm_pid"
      class="$fm_class"
      title="$fm_title"
      log "Switched target to background file manager: $title"
    fi
  fi

  local target_dir
  if [[ -z "$pid" || "$pid" == "||" ]]; then
    target_dir="$FALLBACK_DIR"
  else
    target_dir=$(resolve_cwd "$pid" "$class" "$title")
  fi

  log "Final target: $target_dir"

  case "$mode" in
  term) spawn_terminal "$target_dir" ;;
  files) spawn_files_gui "$target_dir" ;;
  yazi) spawn_files_tui "$target_dir" ;;
  esac
}

main "$@"
