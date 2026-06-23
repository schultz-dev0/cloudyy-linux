#!/usr/bin/env bash
# Usage: search.sh <query>
# Outputs newline-delimited JSON to stdout.
# Each line is one of:
#   {"type":"app","name":"Firefox","icon":"firefox","exec":"firefox","wmclass":"firefox"}
#   {"type":"file","name":"notes.md","path":"/home/user/Documents/notes.md"}

query="${1:-}"
[[ -z "$query" ]] && exit 0

MAX_FILE="${MAX_FILE_RESULTS:-10}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_RESOLVE="${SCRIPT_DIR}/../../overview/services/icon_resolve.py"

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
    icon_path=$(python3 "$ICON_RESOLVE" resolve "$icon" "$desktop_id" "$wmclass" "$exec" 2>/dev/null || true)
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
if [[ ${#query} -ge 3 ]]; then
    search_paths() {
        fd --ignore-case --max-depth 3 --max-results "$MAX_FILE" -- "$1" "$HOME" 2>/dev/null
    }
    mapfile -t file_matches < <(
        {
            search_paths "$query"
            # camelCase → "RustProjects" also matches rust + projects path segments
            if [[ "$query" =~ [a-z][A-Z] ]]; then
                split=$(printf '%s' "$query" | sed 's/\([a-z]\)\([A-Z]\)/\1 \2/g')
                for part in $split; do
                    [[ ${#part} -ge 3 ]] && search_paths "$part"
                done
            fi
        } | awk '!seen[$0]++'
    )
    for path in "${file_matches[@]}"; do
        [[ -z "$path" ]] && continue
        name=$(basename "$path")
        jq -cn --arg name "$name" --arg path "$path" \
          '{type:"file",name:$name,path:$path}'
    done
fi
