#!/usr/bin/env bash
# Usage: search.sh <query>
# Outputs newline-delimited JSON to stdout.
# Each line is one of:
#   {"type":"app","name":"Firefox","icon":"firefox","exec":"firefox","wmclass":"firefox"}
#   {"type":"file","name":"notes.md","path":"/home/user/Documents/notes.md"}

query="${1:-}"
[[ -z "$query" ]] && exit 0

MAX_FILE="${MAX_FILE_RESULTS:-10}"

get_icon_theme() {
    local theme
    theme=$(grep -m1 '^gtk-icon-theme-name=' "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2- | tr -d '\r')
    if [[ -z "$theme" ]] && command -v gtk-query-settings >/dev/null 2>&1; then
        theme=$(gtk-query-settings 2>/dev/null | sed -n 's/.*gtk-icon-theme-name: "\(.*\)"/\1/p' | head -n1)
    fi
    printf '%s\n' "${theme:-Adwaita}"
}

ICON_THEME="$(get_icon_theme)"
icon_dirs=()
for dir in \
    "$HOME/.local/share/icons/$ICON_THEME" \
    "$HOME/.icons/$ICON_THEME" \
    "/usr/share/icons/$ICON_THEME" \
    "$HOME/.local/share/icons/hicolor" \
    "$HOME/.icons/hicolor" \
    "/usr/share/icons/hicolor" \
    "$HOME/.local/share/icons/Papirus" \
    "$HOME/.local/share/icons/Papirus-Dark" \
    "$HOME/.icons/Papirus" \
    "$HOME/.icons/Papirus-Dark" \
    "/usr/share/icons/Papirus" \
    "/usr/share/icons/Papirus-Dark" \
    "$HOME/.local/share/icons/Adwaita" \
    "$HOME/.icons/Adwaita" \
    "/usr/share/icons/Adwaita" \
    "$HOME/.local/share/icons" \
    "$HOME/.icons" \
    "/usr/share/icons" \
    "$HOME/.local/share/pixmaps" \
    "/usr/share/pixmaps"
do
    [[ -d "$dir" ]] && icon_dirs+=("$dir")
done

resolve_icon_path() {
    local candidate normalized dir match expanded

    for candidate in "$@"; do
        [[ -z "$candidate" ]] && continue
        normalized="${candidate#file://}"

        # Handle absolute paths
        if [[ "$normalized" = /* && -f "$normalized" ]]; then
            printf '%s\n' "$normalized"
            return 0
        fi

        # Handle tilde paths
        if [[ "$normalized" = \~/* ]]; then
            expanded="${normalized/#\~/$HOME}"
            if [[ -f "$expanded" ]]; then
                printf '%s\n' "$expanded"
                return 0
            fi
        fi

        normalized="${normalized##*/}"
        normalized="${normalized%.*}"
        [[ -z "$normalized" ]] && continue

        for dir in "${icon_dirs[@]}"; do
            match=$(find "$dir" -type f \( \
                -iname "${normalized}.svg" -o \
                -iname "${normalized}.png" -o \
                -iname "${normalized}.xpm" -o \
                -iname "${normalized}.ico" \
            \) -print -quit 2>/dev/null)
            if [[ -n "$match" ]]; then
                printf '%s\n' "$match"
                return 0
            fi
        done
    done

    return 1
}

mapfile -t app_dirs < <(
    for d in "/usr/share/applications" "$HOME/.local/share/applications"; do
        [[ -d "$d" ]] && echo "$d"
    done
)

# ── App search ─────────────────────────────────────────────────────────────
mapfile -t desktop_matches < <(
    grep -rl "^Name=" "${app_dirs[@]}" 2>/dev/null \
    | xargs grep -lFi -- "$query"      2>/dev/null \
    | head -8
)

for desktop in "${desktop_matches[@]}"; do
    name=$(grep -m1 "^Name=" "$desktop" 2>/dev/null | cut -d= -f2- | tr -d '\r')
    icon=$(grep -m1 "^Icon=" "$desktop" 2>/dev/null | cut -d= -f2- | tr -d '\r')
    exec_raw=$(grep -m1 "^Exec=" "$desktop" 2>/dev/null | cut -d= -f2- | tr -d '\r')
    exec=$(printf '%s' "$exec_raw" | sed 's/ %[a-zA-Z]//g')
    wmclass=$(grep -m1 "^StartupWMClass=" "$desktop" 2>/dev/null | cut -d= -f2-)
    [[ -z "$wmclass" ]] && wmclass=$(basename "${exec%% *}" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    desktop_id=$(basename "$desktop" .desktop)
    exec_base=$(basename "${exec%% *}" 2>/dev/null)
    icon_path=$(resolve_icon_path "$icon" "$desktop_id" "$wmclass" "$exec_base")
    [[ -z "$name" || -z "$exec" ]] && continue
    jq -cn \
      --arg name    "$name" \
      --arg icon    "${icon:-application-x-executable}" \
      --arg iconPath "${icon_path:-}" \
      --arg exec    "$exec" \
      --arg wmclass "$wmclass" \
      '{type:"app",name:$name,icon:$icon,iconPath:$iconPath,exec:$exec,wmclass:$wmclass}'
done

# ── File search ─────────────────────────────────────────────────────────────
if [[ ${#query} -ge 4 ]]; then
    fd --ignore-case --max-depth 2 --max-results "$MAX_FILE" -- "$query" "$HOME" 2>/dev/null \
    | while IFS= read -r path; do
        name=$(basename "$path")
        jq -cn --arg name "$name" --arg path "$path" \
          '{type:"file",name:$name,path:$path}'
    done
fi
