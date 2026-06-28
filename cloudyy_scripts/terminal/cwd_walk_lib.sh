#!/usr/bin/env bash
# Shared cwd resolution helpers for cwd_walk.sh and cwd_walk_test.sh

readonly CWD_WALK_TERMINALS=(kitty Alacritty alacritty foot ghostty wezterm)
readonly CWD_WALK_KITTY_SOCKET="${KITTY_LISTEN_ON:-unix:/tmp/kitty}"

cwd_walk_expand_path() {
  local p=$1
  [[ -z "$p" ]] && return 1
  if [[ "$p" == "~"* ]]; then
    p="${p/#\~/$HOME}"
  fi
  printf '%s' "$p"
}

cwd_walk_is_terminal() {
  local class=$1 t
  for t in "${CWD_WALK_TERMINALS[@]}"; do
    [[ "${class,,}" == "${t,,}" ]] && return 0
  done
  return 1
}

cwd_walk_is_descendant() {
  local ancestor=$1 child=$2 p=$child
  while [[ "$p" -gt 1 ]]; do
    [[ "$p" -eq "$ancestor" ]] && return 0
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [[ -z "$p" ]] && break
  done
  return 1
}

cwd_walk_looks_like_full_path() {
  local title=$1
  [[ "$title" == /* || "$title" == "~"* ]]
}

cwd_walk_strip_thunar_title_suffix() {
  local title=$1
  title="${title% — Thunar}"
  title="${title% - Thunar}"
  printf '%s' "$title"
}

cwd_walk_resolve_thunar_title() {
  local title=$1 path
  path=$(cwd_walk_strip_thunar_title_suffix "$title")
  cwd_walk_looks_like_full_path "$path" || return 1
  path=$(cwd_walk_expand_path "$path") || return 1
  [[ -d "$path" ]] || return 1
  printf '%s' "$path"
}

# Generic: open location bar (Ctrl+L), copy path, restore clipboard.
# Works for any file manager that uses Ctrl+L for the location bar.
cwd_walk_resolve_location_bar() {
  local address=$1 old_clipboard path

  command -v wl-copy &>/dev/null && command -v wl-paste &>/dev/null || return 1

  old_clipboard=$(wl-paste 2>/dev/null || true)

  hyprctl dispatch sendshortcut "CTRL, L, address:${address}" >/dev/null
  sleep 0.08
  hyprctl dispatch sendshortcut "CTRL, A, address:${address}" >/dev/null
  sleep 0.04
  hyprctl dispatch sendshortcut "CTRL, C, address:${address}" >/dev/null
  sleep 0.06
  path=$(wl-paste 2>/dev/null || true)
  hyprctl dispatch sendshortcut "Escape, address:${address}" >/dev/null
  printf '%s' "$old_clipboard" | wl-copy 2>/dev/null || true

  [[ -n "$path" ]] || return 1

  case "$path" in
    file://*) path="${path#file://}" ;;
    sftp://*|ssh://*) return 1 ;;
  esac

  path=$(cwd_walk_expand_path "$path") || return 1
  [[ -d "$path" ]] || return 1
  printf '%s' "$path"
}

cwd_walk_resolve_kitty_cwd() {
  local hypr_pid=$1 json wpid cwd tab_active focused

  command -v kitty &>/dev/null || return 1
  json=$(kitty @ ls --to "$CWD_WALK_KITTY_SOCKET" 2>/dev/null) || return 1

  while IFS=$'\t' read -r tab_active focused wpid cwd; do
    [[ -z "$wpid" || -z "$cwd" ]] && continue
    cwd_walk_is_descendant "$hypr_pid" "$wpid" || continue
    [[ "$tab_active" == "true" && "$focused" == "true" && -d "$cwd" ]] && {
      printf '%s' "$cwd"
      return 0
    }
  done < <(jq -r '
    .[] | .tabs[] as $tab |
    $tab.windows[] |
    [
      ($tab.is_active // false | tostring),
      (.is_focused // false | tostring),
      (.pid // empty | tostring),
      (.cwd // empty)
    ] | @tsv
  ' <<< "$json")

  while IFS=$'\t' read -r tab_active focused wpid cwd; do
    [[ -z "$wpid" || -z "$cwd" ]] && continue
    cwd_walk_is_descendant "$hypr_pid" "$wpid" || continue
    [[ -d "$cwd" ]] && {
      printf '%s' "$cwd"
      return 0
    }
  done < <(jq -r '
    .[] | .tabs[] as $tab |
    $tab.windows[] |
    [
      ($tab.is_active // false | tostring),
      (.is_focused // false | tostring),
      (.pid // empty | tostring),
      (.cwd // empty)
    ] | @tsv
  ' <<< "$json")

  return 1
}

cwd_walk_resolve_terminal_proc_cwd() {
  local root_pid=$1 pid comm cwd

  for pid in $(pgrep -P "$root_pid" 2>/dev/null); do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$comm" in
      zsh|bash|fish|sh)
        cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
        [[ -n "$cwd" && -d "$cwd" ]] && { printf '%s' "$cwd"; return 0; }
        ;;
    esac
    if cwd=$(cwd_walk_resolve_terminal_proc_cwd "$pid"); then
      printf '%s' "$cwd"
      return 0
    fi
  done
  return 1
}

# Resolve cwd from the currently focused window. Prints path or returns 1.
cwd_walk_resolve_focused() {
  local window_info active_class active_pid active_address active_title cwd

  window_info=$(hyprctl activewindow -j)
  active_class=$(jq -r '.class // empty' <<< "$window_info")
  active_pid=$(jq -r '.pid // 0' <<< "$window_info")
  active_address=$(jq -r '.address // empty' <<< "$window_info")
  active_title=$(jq -r '.title // empty' <<< "$window_info")

  [[ -n "$active_class" ]] || return 1

  case "${active_class,,}" in
    thunar)
      if cwd=$(cwd_walk_resolve_thunar_title "$active_title"); then
        printf '%s' "$cwd"
        return 0
      fi
      if [[ -n "$active_address" ]] \
        && cwd=$(cwd_walk_resolve_location_bar "$active_address"); then
        printf '%s' "$cwd"
        return 0
      fi
      return 1
      ;;
    nautilus|org.gnome.nautilus)
      if [[ -n "$active_address" ]] \
        && cwd=$(cwd_walk_resolve_location_bar "$active_address"); then
        printf '%s' "$cwd"
        return 0
      fi
      return 1
      ;;
    *)
      if cwd_walk_is_terminal "$active_class"; then
        if [[ "${active_class,,}" == "kitty" ]] \
          && cwd=$(cwd_walk_resolve_kitty_cwd "$active_pid"); then
          printf '%s' "$cwd"
          return 0
        fi
        if cwd=$(cwd_walk_resolve_terminal_proc_cwd "$active_pid"); then
          printf '%s' "$cwd"
          return 0
        fi
      fi
      return 1
      ;;
  esac
}
