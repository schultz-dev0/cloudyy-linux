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
# ponytail: grep -r avoids xargs splitting paths with spaces (Steam game names).
# One python3 call parses the whole match set (name/exec/wmclass/id). Icon-name
# → file resolution is left to the QML IconResolver (indexed, cached shell-wide);
# doing per-match `resolve` here spawned 16 gi/Gtk-importing pythons per search —
# ~97% of its CPU.
mapfile -t desktop_matches < <(
    grep -rlFi -- "$query" "${app_dirs[@]}" 2>/dev/null \
    | grep '\.desktop$' \
    | head -8
)
[[ ${#desktop_matches[@]} -gt 0 ]] \
    && python3 "$ICON_RESOLVE" apps-batch "${desktop_matches[@]}" 2>/dev/null || true

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
