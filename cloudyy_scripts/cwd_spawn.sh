#!/usr/bin/env bash
# =============================================================================
# cwd_spawn.sh — Context-Aware Directory Spawner
#
# KITTY REQUIREMENT — add these two lines to kitty.conf:
#   allow_remote_control yes
#   listen_on unix:/tmp/kitty-{kitty_pid}
# Then restart kitty. Without this, the API fallback is used instead.
#
# Usage:
#   cwd_spawn.sh term       — open kitty in focused window's CWD
#   cwd_spawn.sh files      — open thunar in focused window's CWD
#   cwd_spawn.sh yazi       — open yazi (TUI) in focused window's CWD
#
# Debug:
#   DEBUG=1 ~/cloudyy_scripts/cwd_spawn.sh term && cat /tmp/cwd_spawn.log
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

# Electron code editors — resolved via title parsing + state.vscdb
readonly -a KNOWN_CODE_EDITORS=(
    codium vscodium code vscode
)
readonly -a KNOWN_SHELLS=(
    bash zsh fish sh dash ksh tcsh
)

# Processes that are terminal internals — never reflect the user's CWD
readonly -a IGNORED_PROCS=(
    kitten          # kitty internal subprocess
    kitty           # kitty itself
    ".kitty-wrapped" # some distros wrap kitty
    login           # login shell wrapper
    sshd            # ssh daemon
)

# =============================================================================
# LOGGING
# =============================================================================

log()  { [[ "$DEBUG" == "1" ]] && echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2 || true; }
warn() { echo "[cwd_spawn] WARN: $*" >&2; }

# =============================================================================
# HYPRCTL
# =============================================================================

get_active_window_info() {
    local json
    json=$(hyprctl activewindow -j 2>/dev/null) || { echo "||"; return; }
    [[ -z "$json" || "$json" == "null" || "$json" == "{}" ]] && { echo "||"; return; }
    python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(str(d.get('pid','')), d.get('class','').lower(), d.get('title',''), sep='|')
" <<< "$json" 2>/dev/null || echo "||"
}

# =============================================================================
# PROC HELPERS
# =============================================================================

read_proc_cwd()  { [[ -d "/proc/$1" ]] && readlink "/proc/$1/cwd"  2>/dev/null || true; }
read_proc_comm() { cat "/proc/$1/comm" 2>/dev/null | tr -d '\n'    || true; }

read_proc_env_var() {
    # read_proc_env_var <pid> <VAR_NAME>
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null \
        | grep "^${2}=" | cut -d= -f2- | head -1 || true
}

is_shell() {
    local comm="$1"
    for sh in "${KNOWN_SHELLS[@]}"; do
        [[ "$comm" == "$sh" || "$comm" == "-$sh" ]] && return 0
    done
    return 1
}

is_code_editor_class() {
    local class="$1"
    for e in "${KNOWN_CODE_EDITORS[@]}"; do
        [[ "$class" == *"$e"* ]] && return 0
    done
    return 1
}

is_ignored_proc() {
    local comm="$1"
    for p in "${IGNORED_PROCS[@]}"; do
        [[ "$comm" == "$p" ]] && return 0
    done
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
    local children
    children=$(pgrep -P "$1" 2>/dev/null) || return 0
    for c in $children; do echo "$c"; get_all_descendants "$c"; done
}

# =============================================================================
# KITTY RESOLUTION
#
# Strategy waterfall:
#   1. Find the kitty socket (KITTY_LISTEN_ON from process or child environs,
#      or scan /proc/net/unix for kitty sockets)
#   2. Call `kitty @ ls` → parse focused window CWD directly  ← most accurate
#   3. Fall back to KITTY_WINDOW_ID matching via child environs ← no API needed
#   4. Last resort: generic process tree walk
# =============================================================================

find_kitty_socket() {
    local kitty_pid="$1"

    # 1a. Check kitty's own environ for KITTY_LISTEN_ON
    local sock
    sock=$(read_proc_env_var "$kitty_pid" "KITTY_LISTEN_ON")
    if [[ -n "$sock" ]]; then
        log "Socket from kitty environ: $sock"
        echo "$sock"; return
    fi

    # 1b. Check any child process environ (shells inherit KITTY_LISTEN_ON)
    local child
    for child in $(get_all_descendants "$kitty_pid" | head -20); do
        sock=$(read_proc_env_var "$child" "KITTY_LISTEN_ON" 2>/dev/null)
        if [[ -n "$sock" ]]; then
            log "Socket from child $child environ: $sock"
            echo "$sock"; return
        fi
    done

    # 1c. Broad scan of /proc/net/unix — catches any listen_on path the user
    #     configured (e.g. unix:/tmp/kitty, unix:/tmp/kitty-{uid}/{pid}-{n},
    #     or anything else). We verify ownership by checking /proc/<pid>/fd
    #     for a file descriptor pointing at the socket path.
    local -a all_sockets=()
    while IFS= read -r line; do
        local path="${line##* }"
        [[ "$path" == /* ]] || continue
        [[ -S "$path" ]]    || continue
        all_sockets+=("$path")
    done < /proc/net/unix 2>/dev/null

    local fd_dir="/proc/${kitty_pid}/fd"
    if [[ -d "$fd_dir" ]]; then
        for sock_path in "${all_sockets[@]}"; do
            while IFS= read -r fd_entry; do
                local resolved
                resolved=$(readlink "$fd_entry" 2>/dev/null) || continue
                if [[ "$resolved" == "$sock_path" ]]; then
                    log "Socket from fd scan: $sock_path"
                    echo "unix:$sock_path"; return
                fi
            done < <(find "$fd_dir" -maxdepth 1 -type l 2>/dev/null)
        done
    fi

    log "No kitty socket found"
    echo ""
}

kitty_api_cwd() {
    local socket="$1"
    kitty @ --to "$socket" ls 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for osw in data:
        for tab in osw.get('tabs', []):
            if not tab.get('is_focused'):
                continue
            for win in tab.get('windows', []):
                if win.get('is_focused'):
                    print(win.get('cwd', ''))
                    sys.exit(0)
except:
    pass
" 2>/dev/null || true
}

# Fallback: match focused pane via KITTY_WINDOW_ID in child process environs.
# hyprctl gives us the window title which kitty sets to the running command —
# but that's fragile. Instead we read KITTY_WINDOW_ID from each child's
# /proc/[pid]/environ and compare against the focused window ID from `kitty @`.
# Without the API this is the next best option: find the foreground shell
# that isn't sitting at $HOME while all others are.
kitty_windowid_cwd() {
    local kitty_pid="$1"
    local -a descendants
    mapfile -t descendants < <(get_all_descendants "$kitty_pid")

    log "KITTY_WINDOW_ID fallback: scanning ${#descendants[@]} descendants"

    # Group CWDs by window ID
    # For each window, track best shell CWD and best non-shell CWD separately
    declare -A wid_shell_cwd wid_nonshell_cwd
    for pid in "${descendants[@]}"; do
        [[ -d "/proc/$pid" ]] || continue
        local cwd comm wid
        cwd=$(read_proc_cwd "$pid");  [[ -z "$cwd" || ! -d "$cwd" ]] && continue
        comm=$(read_proc_comm "$pid")

        # Skip terminal-internal processes — they never reflect user navigation
        is_ignored_proc "$comm" && continue

        wid=$(read_proc_env_var "$pid" "KITTY_WINDOW_ID")
        [[ -z "$wid" ]] && continue

        log "  pid=$pid comm=$comm wid=$wid cwd=$cwd"

        local depth
        depth=$(tr -cd '/' <<< "$cwd" | wc -c)

        if is_shell "$comm"; then
            local existing="${wid_shell_cwd[$wid]:-}"
            local existing_depth=0
            [[ -n "$existing" ]] && existing_depth=$(tr -cd '/' <<< "$existing" | wc -c)
            if [[ -z "$existing" || $depth -gt $existing_depth ]]; then
                wid_shell_cwd[$wid]="$cwd"
            fi
        else
            local existing="${wid_nonshell_cwd[$wid]:-}"
            local existing_depth=0
            [[ -n "$existing" ]] && existing_depth=$(tr -cd '/' <<< "$existing" | wc -c)
            if [[ -z "$existing" || $depth -gt $existing_depth ]]; then
                wid_nonshell_cwd[$wid]="$cwd"
            fi
        fi
    done

    # Merge: prefer non-shell CWD per window (it means a program is running there)
    # but only if it is deeper than or equal to the shell CWD — guards against
    # editors that were opened from HOME and haven't changed directory
    declare -A wid_to_cwd
    for wid in "${!wid_shell_cwd[@]}"; do
        local sc="${wid_shell_cwd[$wid]:-}"
        local nc="${wid_nonshell_cwd[$wid]:-}"
        local sc_depth=0 nc_depth=0
        [[ -n "$sc" ]] && sc_depth=$(tr -cd '/' <<< "$sc" | wc -c)
        [[ -n "$nc" ]] && nc_depth=$(tr -cd '/' <<< "$nc" | wc -c)
        if [[ -n "$nc" && $nc_depth -ge $sc_depth ]]; then
            wid_to_cwd[$wid]="$nc"
        else
            wid_to_cwd[$wid]="$sc"
        fi
    done
    # Also catch windows that only have non-shell children
    for wid in "${!wid_nonshell_cwd[@]}"; do
        [[ -z "${wid_to_cwd[$wid]:-}" ]] && wid_to_cwd[$wid]="${wid_nonshell_cwd[$wid]}"
    done

    if [[ ${#wid_to_cwd[@]} -eq 0 ]]; then
        log "No KITTY_WINDOW_IDs found in child environs"
        echo ""; return
    fi

    # If only one unique window, return its CWD
    if [[ ${#wid_to_cwd[@]} -eq 1 ]]; then
        local only_cwd
        only_cwd="${wid_to_cwd[*]}"
        log "Single kitty window, CWD: $only_cwd"
        echo "$only_cwd"; return
    fi

    # Multiple windows: prefer the one whose CWD is NOT $HOME
    # (the focused one the user is actually working in is most likely not home)
    local best=""
    for wid in "${!wid_to_cwd[@]}"; do
        local c="${wid_to_cwd[$wid]}"
        if [[ "$c" != "$HOME" ]]; then
            best="$c"
            log "Preferred non-home window wid=$wid cwd=$c"
            break
        fi
    done

    echo "${best:-${wid_to_cwd[*]% *}}"
}

resolve_kitty_cwd() {
    local kitty_pid="$1"

    # --- Strategy 1: kitty remote API ---
    local socket
    socket=$(find_kitty_socket "$kitty_pid")

    if [[ -n "$socket" ]]; then
        local api_cwd
        api_cwd=$(kitty_api_cwd "$socket")
        if [[ -n "$api_cwd" && -d "$api_cwd" ]]; then
            log "kitty API success: $api_cwd"
            echo "$api_cwd"; return
        fi
        log "kitty API returned empty/invalid: '${api_cwd:-}'"
    fi

    # --- Strategy 2: KITTY_WINDOW_ID matching ---
    local wid_cwd
    wid_cwd=$(kitty_windowid_cwd "$kitty_pid")
    if [[ -n "$wid_cwd" && -d "$wid_cwd" ]]; then
        log "KITTY_WINDOW_ID fallback success: $wid_cwd"
        echo "$wid_cwd"; return
    fi

    # --- Strategy 3: generic tree walk ---
    log "All kitty strategies failed, using generic tree walk"
    resolve_terminal_cwd_generic "$kitty_pid"
}

# =============================================================================
# GENERIC TERMINAL TREE WALK
# =============================================================================

resolve_terminal_cwd_generic() {
    local term_pid="$1"
    local -a descendants
    mapfile -t descendants < <(get_all_descendants "$term_pid")

    log "Generic walk: ${#descendants[@]} descendants of PID $term_pid"

    local best_non_shell="" best_shell="" best_any=""
    local best_non_shell_depth=0 best_shell_depth=0

    for pid in "${descendants[@]}"; do
        [[ -d "/proc/$pid" ]] || continue
        local cwd comm
        cwd=$(read_proc_cwd "$pid");  [[ -z "$cwd" || ! -d "$cwd" || "$cwd" == "/" ]] && continue
        comm=$(read_proc_comm "$pid")

        # Skip terminal-internal processes — their CWD is meaningless for navigation
        is_ignored_proc "$comm" && continue

        log "  pid=$pid comm=$comm cwd=$cwd"

        local depth
        depth=$(tr -cd '/' <<< "$cwd" | wc -c)

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

    # Prefer non-shell only when it is at least as deep as the shell CWD
    local result
    if [[ -n "$best_non_shell" && $best_non_shell_depth -ge $best_shell_depth ]]; then
        result="$best_non_shell"
    else
        result="${best_shell:-${best_non_shell:-${best_any:-}}}"
    fi
    log "Generic walk result: '${result}'"
    if [[ -n "$result" && -d "$result" ]]; then
        echo "$result"
    else
        read_proc_cwd "$term_pid"
    fi
}

# =============================================================================
# FILE MANAGER (title + FD scan)
# =============================================================================

resolve_file_manager_cwd() {
    local pid="$1" title="$2"

    # --- Parse folder name from window title ---
    # Thunar sets title to "FolderName - Thunar"
    # Strip the suffix with python to avoid sed unicode/locale issues
    local folder_hint
    folder_hint=$(python3 -c "
import sys, re
t = sys.argv[1]
t = re.sub(r'\s*[—–-]\s*(Thunar|Files|File Manager)\s*$', '', t, flags=re.IGNORECASE).strip()
print(t)
" "$title" 2>/dev/null)

    log "File manager hint: '${folder_hint}'"

    [[ -z "$folder_hint" ]] && { echo "$HOME"; return; }

    # --- Exact match: XDG standard dirs (instant, no search needed) ---
    declare -A xdg_dirs=(
        ["Home"]="$HOME"
        ["$(basename "$HOME")"]="$HOME"
        ["Downloads"]="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
        ["Documents"]="${XDG_DOCUMENTS_DIR:-$HOME/Documents}"
        ["Pictures"]="${XDG_PICTURES_DIR:-$HOME/Pictures}"
        ["Music"]="${XDG_MUSIC_DIR:-$HOME/Music}"
        ["Videos"]="${XDG_VIDEOS_DIR:-$HOME/Videos}"
        ["Desktop"]="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
        ["Templates"]="${XDG_TEMPLATES_DIR:-$HOME/Templates}"
        ["Public"]="${XDG_PUBLICSHARE_DIR:-$HOME/Public}"
    )
    if [[ -n "${xdg_dirs[$folder_hint]:-}" && -d "${xdg_dirs[$folder_hint]}" ]]; then
        log "XDG match: ${xdg_dirs[$folder_hint]}"
        echo "${xdg_dirs[$folder_hint]}"
        return
    fi

    # --- Filesystem search: find all dirs named $folder_hint under $HOME ---
    # Use mtime (not atime — disabled by relatime on most Linux systems)
    # Limit to depth 6 for performance; prune hidden dirs to avoid noise
    log "Searching \$HOME for dir named: '${folder_hint}'"

    local best
    best=$(find "$HOME"         -maxdepth 6         -type d         -name "$folder_hint"         ! -path "*/.*"         -printf "%T@ %p
" 2>/dev/null         | sort -rn         | head -1         | cut -d" " -f2-)

    if [[ -n "$best" && -d "$best" ]]; then
        log "Filesystem search found: $best"
        echo "$best"
        return
    fi

    # --- Last resort: include hidden dirs in search ---
    log "Retrying with hidden dirs included"
    best=$(find "$HOME"         -maxdepth 6         -type d         -name "$folder_hint"         -printf "%T@ %p
" 2>/dev/null         | sort -rn         | head -1         | cut -d" " -f2-)

    if [[ -n "$best" && -d "$best" ]]; then
        log "Hidden dir search found: $best"
        echo "$best"
        return
    fi

    warn "Could not resolve '${folder_hint}' — using HOME"
    echo "$HOME"
}

# =============================================================================
# VSCODIUM / VSCODE RESOLUTION
#
# Title format: "{filename} - {workspace_name} - VSCodium"
# Workspace name is always the second-to-last " - " segment.
# Fallback: query state.vscdb (SQLite) for the active folder URI.
# =============================================================================

resolve_vscodium_cwd() {
    local title="$1"

    # Title format: "{filename} - {workspace_or_profile} - VSCodium"
    # Parse both parts — the open filename is the most actionable signal
    local file_hint workspace_hint
    read -r file_hint workspace_hint < <(python3 -c "
import sys
t = sys.argv[1]
for suffix in [' - VSCodium', ' - Code - OSS', ' - Code', ' - VSCode']:
    if t.endswith(suffix):
        t = t[:-len(suffix)]
        break
parts = t.split(' - ', 1)
file_hint = parts[0].strip()
workspace_hint = parts[1].strip() if len(parts) > 1 else ''
print(file_hint, workspace_hint)
" "$title" 2>/dev/null)

    log "VSCodium file_hint='${file_hint}' workspace_hint='${workspace_hint}'"

    # --- Strategy 1: find the open file, walk up to project root ---
    # The filename in the title is the currently focused editor tab.
    # Find it on disk, then walk up looking for a project root marker.
    if [[ -n "$file_hint" && "$file_hint" != "Welcome" && "$file_hint" != "untitled" ]]; then
        local found_file
        found_file=$(find "$HOME" \
            -maxdepth 8 \
            -type f \
            -name "$file_hint" \
            ! -path "*/.*" \
            -printf "%T@ %p\n" 2>/dev/null \
            | sort -rn \
            | head -1 \
            | cut -d" " -f2-)

        if [[ -n "$found_file" && -f "$found_file" ]]; then
            log "Found open file: $found_file"

            # Walk up from the file's directory toward HOME, stopping at the
            # deepest directory that contains a recognised project root marker.
            local dir project_root
            dir="$(dirname "$found_file")"
            project_root="$dir"   # sensible default: file's own directory

            while [[ "$dir" != "$HOME" && "$dir" != "/" ]]; do
                for marker in \
                    .git \
                    Cargo.toml \
                    package.json \
                    pyproject.toml \
                    setup.py \
                    go.mod \
                    CMakeLists.txt \
                    Makefile \
                    flake.nix \
                    .envrc \
                    .project; do
                    if [[ -e "${dir}/${marker}" ]]; then
                        project_root="$dir"
                        log "Project root marker '${marker}' at: $dir"
                        break 2
                    fi
                done
                dir="$(dirname "$dir")"
            done

            log "Resolved project root: $project_root"
            echo "$project_root"
            return
        fi
        log "File '${file_hint}' not found on disk, trying workspace hint"
    fi

    # --- Strategy 2: workspace hint is an actual folder name ---
    # Skip if it matches the username/home basename — that's a profile name not a folder
    local home_basename
    home_basename="$(basename "$HOME")"
    if [[ -n "$workspace_hint" \
       && "$workspace_hint" != "$home_basename" \
       && "$workspace_hint" != "$USER" ]]; then

        local best
        best=$(find "$HOME" \
            -maxdepth 6 \
            -type d \
            -name "$workspace_hint" \
            ! -path "*/.*" \
            -printf "%T@ %p\n" 2>/dev/null \
            | sort -rn \
            | head -1 \
            | cut -d" " -f2-)

        if [[ -n "$best" && -d "$best" ]]; then
            log "Workspace dir found: $best"
            echo "$best"
            return
        fi
    fi

    # --- Strategy 3: state.vscdb most recently opened folder ---
    local vscdb="${HOME}/.config/VSCodium/User/globalStorage/state.vscdb"
    [[ ! -f "$vscdb" ]] && vscdb="${HOME}/.config/Code/User/globalStorage/state.vscdb"

    if [[ -f "$vscdb" ]] && command -v sqlite3 &>/dev/null; then
        local db_result
        db_result=$(sqlite3 "$vscdb" \
            "SELECT value FROM ItemTable
             WHERE key = 'history.recentlyOpenedPathsList'
             LIMIT 1;" 2>/dev/null \
            | python3 -c "
import sys, json, urllib.parse, os
try:
    d = json.loads(sys.stdin.read())
except:
    sys.exit(1)
for e in d.get('entries', []):
    if not isinstance(e, dict): continue
    uri = e.get('folderUri', '')
    if uri.startswith('file://'):
        path = urllib.parse.unquote(uri[7:]).rstrip('/')
        if os.path.isdir(path) and path != os.path.expanduser('~'):
            print(path)
            sys.exit(0)
" 2>/dev/null)

        if [[ -n "$db_result" && -d "$db_result" ]]; then
            log "state.vscdb recent folder: $db_result"
            echo "$db_result"
            return
        fi
    fi

    log "All VSCodium strategies failed, using HOME"
    echo "$HOME"
}

# =============================================================================
# DISPATCH
# =============================================================================

resolve_cwd() {
    local pid="$1" class="$2" title="$3"
    local cwd=""

    if [[ "$class" == *"kitty"* ]]; then
        log "Strategy: kitty"
        cwd=$(resolve_kitty_cwd "$pid")
    elif is_code_editor_class "$class"; then
        log "Strategy: VSCodium/VSCode"
        cwd=$(resolve_vscodium_cwd "$title")
    elif is_file_manager_class "$class"; then
        log "Strategy: file manager"
        cwd=$(resolve_file_manager_cwd "$pid" "$title")
    elif is_terminal_class "$class"; then
        log "Strategy: generic terminal"
        cwd=$(resolve_terminal_cwd_generic "$pid")
    else
        log "Strategy: direct proc CWD"
        cwd=$(read_proc_cwd "$pid")
    fi

    if [[ -n "$cwd" && -d "$cwd" ]]; then
        echo "$cwd"
    else
        warn "Resolution failed (got: '${cwd:-empty}') — using $FALLBACK_DIR"
        echo "$FALLBACK_DIR"
    fi
}

# =============================================================================
# LAUNCH
# =============================================================================

spawn_terminal()  {
    log "Spawning kitty in: $1"
    uwsm-app -- "$TERMINAL" --directory "$1" >/dev/null 2>&1 & disown
}
spawn_files_gui() {
    log "Spawning thunar in: $1"
    uwsm-app -- "$FILE_MANAGER_GUI" "$1" >/dev/null 2>&1 & disown
}
spawn_files_tui() {
    log "Spawning yazi in: $1"
    uwsm-app -- "$TERMINAL" --directory "$1" --class "yazi_spawned" \
        -e "$FILE_MANAGER_TUI" "$1" >/dev/null 2>&1 & disown
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local mode="${1:-term}"
    case "$mode" in
        term|files|yazi) ;;
        *) warn "Unknown mode '${mode}'. Valid: term, files, yazi"; exit 1 ;;
    esac

    [[ "$DEBUG" == "1" ]] && : > "$LOG_FILE"
    log "=== cwd_spawn mode=$mode ==="

    local info pid class title
    info=$(get_active_window_info)
    IFS='|' read -r pid class title <<< "$info"

    log "Active window — pid='${pid}' class='${class}' title='${title}'"

    local target_dir
    if [[ -z "$pid" || -z "$class" ]]; then
        warn "No active window. Using fallback."
        target_dir="$FALLBACK_DIR"
    else
        target_dir=$(resolve_cwd "$pid" "$class" "$title")
    fi

    log "Final target: $target_dir"

    case "$mode" in
        term)  spawn_terminal  "$target_dir" ;;
        files) spawn_files_gui "$target_dir" ;;
        yazi)  spawn_files_tui "$target_dir" ;;
    esac
}

main "$@"