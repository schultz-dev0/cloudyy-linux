#!/usr/bin/env bash
# Usage: search.sh <query>
# Outputs newline-delimited JSON to stdout.
# Each line is one of:
#   {"type":"app","name":"Firefox","icon":"firefox","exec":"firefox","wmclass":"firefox"}
#   {"type":"file","name":"notes.md","path":"/home/user/Documents/notes.md"}

query="${1:-}"
[[ -z "$query" ]] && exit 0

MAX_FILE="${MAX_FILE_RESULTS:-10}"

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
    [[ -z "$name" || -z "$exec" ]] && continue
    jq -cn \
      --arg name    "$name" \
      --arg icon    "${icon:-application-x-executable}" \
      --arg exec    "$exec" \
      --arg wmclass "$wmclass" \
      '{type:"app",name:$name,icon:$icon,exec:$exec,wmclass:$wmclass}'
done

# ── File search ─────────────────────────────────────────────────────────────
if [[ ${#query} -ge 4 ]]; then
    fd --max-depth 2 --max-results "$MAX_FILE" -- "$query" "$HOME" 2>/dev/null \
    | while IFS= read -r path; do
        name=$(basename "$path")
        jq -cn --arg name "$name" --arg path "$path" \
          '{type:"file",name:$name,path:$path}'
    done
fi
