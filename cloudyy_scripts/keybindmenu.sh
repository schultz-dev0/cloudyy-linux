#!/usr/bin/env bash
# ==============================================================================
# Description: Advanced TUI for Hyprland Keybinds
#              - Unified View: See Source and Custom binds together.
#              - Smart Grouping: Overrides appear next to originals.
#              - Debloating: Replaces old edits instead of appending forever.
#              - Interactive Auto-Correction (Logic Fixed for 'bind').
#              - Smart Unbind Deduplication.
# Version:     v23.2
# Made by Dusk: https://github.com/dusklinux
# ==============================================================================

set -euo pipefail

# --- Version Check (Bash 5.0+ required) ---
if ((BASH_VERSINFO[0] < 5)); then
  printf 'FATAL: This script requires Bash 5.0 or newer.\n' >&2
  exit 1
fi

# --- ANSI Colors (readonly) ---
readonly BLUE=$'\033[0;34m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly RED=$'\033[0;31m'
readonly CYAN=$'\033[0;36m'
readonly PURPLE=$'\033[0;35m'
readonly GREY=$'\033[0;90m'
readonly BOLD=$'\033[1m'
readonly RESET=$'\033[0m'
readonly BRIGHT_WHITE=$'\033[0;97m'

# --- Paths ---
readonly SOURCE_CONF="${HOME}/.config/hypr/source/bindigs.conf"
readonly CUSTOM_CONF="${HOME}/.config/hypr/user-configs/userbinds.conf"

# --- Sentinel Values ---
readonly CREATE_MARKER_ID="__CREATE_NEW_BIND__"
readonly EMPTY_BIND_TEMPLATE="bindd = "

# --- Globals for cleanup ---
declare -a TEMP_FILES=()

# ==============================================================================
# Helpers
# ==============================================================================

cleanup() {
  local f
  for f in "${TEMP_FILES[@]}"; do
    rm -f -- "$f"
  done
}
trap cleanup EXIT INT TERM HUP

# Create a temp file and register for cleanup.
make_temp() {
  local -n _ref="$1"
  local template="${2:-${TMPDIR:-/tmp}/hyprbinds.XXXXXX}"
  _ref="$(mktemp "$template")" || exit 1
  TEMP_FILES+=("$_ref")
}

die() {
  printf '%s[FATAL]%s %s\n' "$RED" "$RESET" "$1" >&2
  exit 1
}

# Trim leading/trailing whitespace via nameref.
_trim() {
  local -n _out="$1"
  _out="${2#"${2%%[![:space:]]*}"}"
  _out="${_out%"${_out##*[![:space:]]}"}"
}

# Normalize modifiers AND key in-place via nameref.
# Lowercases both and expands $mainmod -> super.
_normalize_bind_parts() {
  local -n _mods="$1"
  local -n _key="$2"
  _mods="${_mods,,}"
  _mods="${_mods//\$mainmod/super}"
  _key="${_key,,}"
}

# Returns 0 if line is blank or a pure comment.
_is_comment_or_blank() {
  [[ -z "$1" || "$1" =~ ^[[:space:]]*# ]]
}

# Returns 0 if line is a bind or unbind directive.
_is_bind_directive() {
  [[ "$1" =~ ^[[:space:]]*(bind[a-z]*|unbind)[[:space:]]*= ]]
}

# Returns 0 if line is specifically an unbind.
_is_unbind() {
  [[ "$1" =~ ^[[:space:]]*unbind[[:space:]]*= ]]
}

# Split content by comma, preserving fields correctly.
# FIXED: The original unconditionally removed the last element, which was wrong.
#        We only remove the last element if it's genuinely empty (from trailing comma).
#        Also fixed: must use if-statement to avoid set -e exit on false condition.
_split_comma() {
  local -n _arr="$1"
  local str="$2"
  _arr=()
  local field=""

  # Read comma-delimited fields. We append a comma to ensure the last field is read.
  while IFS= read -r -d ',' field; do
    _arr+=("$field")
  done <<<"${str},"

  # Only remove the last element if it's empty (handles trailing commas in input).
  # CRITICAL: Must use if-statement, not [[ ]] && cmd, because with set -e,
  # a false [[ ]] would return exit code 1 and kill the script.
  if [[ ${#_arr[@]} -gt 0 && -z "${_arr[-1]}" ]]; then
    unset '_arr[-1]'
  fi
}

# ==============================================================================
# Core Logic
# ==============================================================================

# Filter CUSTOM_CONF, removing any bind/unbind matching target mods+key.
filter_out_bind() {
  local t_mods="$1" t_key="$2"
  _normalize_bind_parts t_mods t_key

  local line content part0 part1 l_mods l_key

  while IFS= read -r line || [[ -n "$line" ]]; do
    if _is_comment_or_blank "$line" || ! _is_bind_directive "$line"; then
      printf '%s\n' "$line"
      continue
    fi

    content="${line#*=}"
    IFS=',' read -r part0 part1 _ <<<"$content"

    _trim l_mods "$part0"
    _trim l_key "$part1"
    _normalize_bind_parts l_mods l_key

    # Drop lines matching target (Case Insensitive Match)
    if [[ "$l_mods" == "$t_mods" && "$l_key" == "$t_key" ]]; then
      continue
    fi

    printf '%s\n' "$line"
  done
}

# Generate sorted list for fzf.
generate_bind_list() {
  local list_out="$1"
  local file tag color
  local line content part0 part1 l_mods l_key sort_key

  {
    for file in "$SOURCE_CONF" "$CUSTOM_CONF"; do
      [[ -f "$file" ]] || continue

      if [[ "$file" == "$SOURCE_CONF" ]]; then
        tag="[SRC] "
        color="$BLUE"
      else
        tag="[CUST]"
        color="$GREEN"
      fi

      while IFS= read -r line || [[ -n "$line" ]]; do
        _is_comment_or_blank "$line" && continue
        _is_bind_directive "$line" || continue
        _is_unbind "$line" && continue

        content="${line#*=}"
        IFS=',' read -r part0 part1 _ <<<"$content"

        _trim l_mods "$part0"
        _trim l_key "$part1"

        local norm_mods="$l_mods" norm_key="$l_key"
        _normalize_bind_parts norm_mods norm_key
        sort_key="${norm_mods} ${norm_key}"

        printf '%s\t%s%s%s %s\t%s\n' \
          "$sort_key" "$color" "$tag" "$RESET" "$line" "$line"
      done <"$file"
    done
  } | sort -t$'\t' -k1,1 | cut -f2- >"$list_out"
}

# Check for keybind conflict.
check_conflict() {
  local check_mods="$1" check_key="$2" file="$3"
  local ignore_mods="${4:-}" ignore_key="${5:-}"

  _trim check_mods "$check_mods"
  _trim check_key "$check_key"
  [[ -z "$check_key" ]] && return 1

  _normalize_bind_parts check_mods check_key

  local norm_ignore_mods="" norm_ignore_key=""
  if [[ -n "$ignore_mods" ]]; then
    norm_ignore_mods="$ignore_mods"
    norm_ignore_key="$ignore_key"
    _normalize_bind_parts norm_ignore_mods norm_ignore_key
  fi

  local line content part0 part1 l_mods l_key
  local last_match=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    _is_comment_or_blank "$line" && continue
    _is_bind_directive "$line" || continue
    _is_unbind "$line" && continue

    content="${line#*=}"
    IFS=',' read -r part0 part1 _ <<<"$content"

    _trim l_mods "$part0"
    _trim l_key "$part1"
    _normalize_bind_parts l_mods l_key

    if [[ "$l_mods" == "$check_mods" && "$l_key" == "$check_key" ]]; then
      if [[ -n "$norm_ignore_mods" &&
        "$l_mods" == "$norm_ignore_mods" &&
        "$l_key" == "$norm_ignore_key" ]]; then
        continue
      fi
      last_match="$line"
    fi
  done <"$file"

  if [[ -n "$last_match" ]]; then
    printf '%s' "$last_match"
    return 0
  fi
  return 1
}

# ==============================================================================
# Main
# ==============================================================================
main() {
  command -v fzf &>/dev/null || die "'fzf' is required but not installed."
  [[ -f "$SOURCE_CONF" ]] || die "Source config missing: $SOURCE_CONF"

  local custom_dir="${CUSTOM_CONF%/*}"
  mkdir -p "$custom_dir"
  [[ -f "$CUSTOM_CONF" ]] || : >"$CUSTOM_CONF"

  # 1. Generate unified bind list
  local list_file
  make_temp list_file
  generate_bind_list "$list_file"

  local create_display="${BOLD}[+] Create New Keybind${RESET}"
  local selected_entry

  if ! selected_entry=$(
    {
      printf '%s\t%s\n' "$create_display" "$CREATE_MARKER_ID"
      cat -- "$list_file"
    } | fzf --ansi --delimiter=$'\t' --with-nth=1 \
      --header="SELECT KEYBIND (SRC = Original, CUST = Your Override)" \
      --info=inline --layout=reverse --border --prompt="Select > "
  ); then
    exit 0
  fi

  # 2. Parse selection
  local raw_line="${selected_entry##*$'\t'}"
  local origin=""

  if [[ "$raw_line" == "$CREATE_MARKER_ID" ]]; then
    origin="NEW"
    raw_line="$EMPTY_BIND_TEMPLATE"
  elif [[ "$selected_entry" == *"[CUST]"* ]]; then
    origin="CUST"
  else
    origin="SRC"
  fi

  # 3. Setup editing context
  local orig_mods="" orig_key=""
  local current_input="$raw_line"

  if [[ "$origin" != "NEW" ]]; then
    local content="${raw_line#*=}"
    local part0 part1
    IFS=',' read -r part0 part1 _ <<<"$content"
    _trim orig_mods "$part0"
    _trim orig_key "$part1"
  fi

  # 4. Interactive edit loop
  local conflict_unbind_cmd=""
  local user_line=""

  while true; do
    clear
    printf '%s┌──────────────────────────────────────────────┐%s\n' "$BLUE" "$RESET"
    printf '%s│ MODE: %-37s│%s\n' "$YELLOW" "${origin} EDIT" "$RESET"
    printf '%s└──────────────────────────────────────────────┘%s\n' "$BLUE" "$RESET"

    if [[ "$origin" != "NEW" ]]; then
      printf ' %sTarget:%s %s\n\n' "$GREY" "$RESET" "$raw_line"
    fi

    # --- Instructions & Help Block ---
    printf '%sINSTRUCTIONS:%s\n' "$CYAN" "$RESET"
    printf ' - Edit the line below directly. Keep the commas!\n'
    printf ' - Default Format: %sbindd = MODS, KEY, DESC, DISPATCHER, ARG%s\n' "$GREEN" "$RESET"
    printf ' - %sNOTE:%s Keys are CASE SENSITIVE! (e.g. "S" is Shift+s, "s" is just s)\n' "$YELLOW" "$RESET"

    printf '\n %sEXAMPLES:%s\n' "$BOLD" "$RESET"
    printf '   1. bindd = $mainMod, Q, Launch Terminal, exec, uwsm-app -- kitty\n'
    printf '   2. bindd = $mainMod, C, Close Window, killactive,\n'
    printf '   3. binded = $mainMod SHIFT, L, Move Right, movewindow, r\n'
    printf '   4. bindd = $mainMod ALT, M, Music Recognition, exec, ~/user_scripts/music/music_recognition.sh\n'
    printf '   5. bindd = $mainMod, S, Screenshot, exec, slurp | grim -g - - | wl-copy\n'

    printf '\n%sFLAGS REFERENCE (Append to bind, e.g. binddl, binddel):%s\n' "$PURPLE" "$RESET"
    printf '  %sd%s  has description  %s(Easier for discerning what the keybind does)%s\n' "$BOLD" "$RESET" "$BRIGHT_WHITE" "$RESET"
    printf '  %sl%s  locked           %s(Works over lockscreen)%s\n' "$BOLD" "$RESET" "$BRIGHT_WHITE" "$RESET"
    printf '  %se%s  repeat           %s(Repeats when held)%s\n' "$BOLD" "$RESET" "$BRIGHT_WHITE" "$RESET"
    printf '  %so%s  long press       %s(Triggers on hold)%s\n' "$BOLD" "$RESET" "$BRIGHT_WHITE" "$RESET"
    printf '  %sm%s  mouse            %s(For mouse clicks)%s\n' "$BOLD" "$RESET" "$BRIGHT_WHITE" "$RESET"

    # --- Input Prompt ---
    printf '\n%sEnter Keybind:%s\n' "$BOLD" "$RESET"
    local prompt=$'\001'"$PURPLE"$'\002''> '$'\001'"$RESET"$'\002'

    if ! IFS= read -e -r -p "$prompt" -i "$current_input" user_line; then
      printf '\nCancelled.\n'
      exit 0
    fi

    [[ -z "$user_line" || "$user_line" == "$EMPTY_BIND_TEMPLATE" ]] && continue

    # Parse user input
    local bind_type="${user_line%%=*}"
    _trim bind_type "$bind_type"
    local content="${user_line#*=}"
    _trim content "$content"

    local -a parts
    _split_comma parts "$content"

    local new_mods="${parts[0]:-}" new_key="${parts[1]:-}"
    _trim new_mods "$new_mods"
    _trim new_key "$new_key"

    if [[ -z "$new_key" ]]; then
      printf '\n%sError: Key is required.%s\n' "$RED" "$RESET"
      read -r -p "Press Enter to continue..."
      continue
    fi

    # --- Interactive Auto-Fix Prompt (Strict Logic) ---
    # If user has >= 5 parts (implying description) and type starts with 'bind'
    if ((${#parts[@]} >= 5)) && [[ "$bind_type" == bind* ]]; then
      # Strip 'bind' prefix to isolate flags (e.g. "bindl" -> "l", "bind" -> "")
      local flags="${bind_type#bind}"

      # Check if 'd' is missing from the remaining flags
      if [[ "$flags" != *d* ]]; then
        local fixed_type="${bind_type}d"
        printf '\n%s[AUTO-FIX]%s Missing "d" flag for description: "%s" → "%s"\n' "$CYAN" "$RESET" "$bind_type" "$fixed_type"
        printf '           %s[Enter]%s Accept fix  %s[e]%s Edit  %s[w]%s Write anyway\n' "$BOLD" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"

        local fix_choice
        read -r -p "Select > " fix_choice

        case "${fix_choice,,}" in
        e*)
          current_input="$user_line"
          continue
          ;;
        w*)
          : # Do nothing, write as-is
          ;;
        *)
          # Default: Accept Fix
          user_line="${fixed_type} = ${content}"
          ;;
        esac
      fi
    fi

    # 5. Conflict detection
    printf '\n%sChecking for conflicts...%s ' "$CYAN" "$RESET"
    local conflict_line=""

    local ignore_m="" ignore_k=""
    if [[ "$origin" == "CUST" ]]; then
      ignore_m="$orig_mods"
      ignore_k="$orig_key"
    fi

    if conflict_line="$(check_conflict "$new_mods" "$new_key" "$CUSTOM_CONF" "$ignore_m" "$ignore_k")"; then
      printf '%sCONFLICT (Custom)!%s\n  %s\n' "$RED" "$RESET" "$conflict_line"
    elif conflict_line="$(check_conflict "$new_mods" "$new_key" "$SOURCE_CONF")"; then
      printf '%sCONFLICT (Source)!%s\n  %s\n' "$RED" "$RESET" "$conflict_line"
    else
      printf '%sNone%s\n' "$GREEN" "$RESET"
    fi

    if [[ -n "$conflict_line" ]]; then
      printf '\n%s[y] Overwrite  [e] Edit conflicting bind  [n] Retry%s\n' "$YELLOW" "$RESET"
      local choice
      read -r -p "Select > " choice

      case "${choice,,}" in
      y*)
        local c_content="${conflict_line#*=}"
        local c_m c_k
        IFS=',' read -r c_m c_k _ <<<"$c_content"
        _trim c_m "$c_m"
        _trim c_k "$c_k"
        conflict_unbind_cmd="unbind = ${c_m}, ${c_k}"
        break
        ;;
      e*)
        current_input="$conflict_line"
        raw_line="$conflict_line"
        origin="CUST"
        local cm ck
        IFS=',' read -r cm ck _ <<<"${conflict_line#*=}"
        _trim orig_mods "$cm"
        _trim orig_key "$ck"
        continue
        ;;
      *)
        current_input="$user_line"
        continue
        ;;
      esac
    fi

    break
  done

  # 6. Write changes atomically (The Debloater)
  local timestamp
  printf -v timestamp '%(%Y-%m-%d %H:%M)T' -1

  local temp_file
  make_temp temp_file "${CUSTOM_CONF}.XXXXXX"

  if [[ "$origin" == "CUST" ]]; then
    # Filter OUT the old version of this keybind from the custom file
    filter_out_bind "$orig_mods" "$orig_key" <"$CUSTOM_CONF" >"$temp_file"
  else
    cat -- "$CUSTOM_CONF" >"$temp_file"
  fi

  {
    printf '\n# [%s] %s\n' "$timestamp" "$origin"

    # Logic to avoid double unbinds
    local src_unbind_cmd=""
    if [[ "$origin" == "SRC" ]]; then
      src_unbind_cmd="unbind = $orig_mods, $orig_key"
      printf '%s\n' "$src_unbind_cmd"
    fi

    if [[ -n "$conflict_unbind_cmd" ]]; then
      if [[ "$conflict_unbind_cmd" != "$src_unbind_cmd" ]]; then
        printf '# Resolved Conflict:\n%s\n' "$conflict_unbind_cmd"
      fi
    fi

    printf '%s\n' "$user_line"
  } >>"$temp_file"

  mv -f -- "$temp_file" "$CUSTOM_CONF"

  printf '\n%s[SUCCESS]%s Saved to %s\n' "$GREEN" "$RESET" "$CUSTOM_CONF"

  if command -v hyprctl &>/dev/null; then
    hyprctl reload &>/dev/null && printf 'Hyprland configuration reloaded.\n'
  fi
}

main "$@"
