#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# waybar_debug.sh v2 — Waybar preset diagnostic + runtime tester
#
# Static checks:  CSS crashes, JSON errors, missing scripts
# Runtime checks: switches preset, reads live logs, diagnoses invisible bars
#
# Usage:
#   waybar_debug.sh                  Scan ALL presets (static)
#   waybar_debug.sh <preset>         Scan one preset (static)
#   waybar_debug.sh --test <preset>  Switch, launch, diagnose live
#   waybar_debug.sh --test-all       Runtime-test every preset
#   waybar_debug.sh --live           Diagnose currently active files
#   waybar_debug.sh --log            Show + parse recent crash logs
#   waybar_debug.sh --processes      Check for stale waybar instances
#   waybar_debug.sh --watch          Live log tail
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

readonly WAYBAR_DIR="${HOME}/.config/waybar"
readonly PRESETS_DIR="${WAYBAR_DIR}/presets"
readonly ACTIVE_CONFIG="${WAYBAR_DIR}/config.jsonc"
readonly ACTIVE_STYLE="${WAYBAR_DIR}/style.css"
readonly CURRENT_PRESET_FILE="${WAYBAR_DIR}/.current_preset"
readonly SWITCH_SCRIPT="${WAYBAR_DIR}/scripts/switch_style.sh"
readonly LAUNCH_SCRIPT="${HOME}/cloudyy_scripts/launch_waybar.sh"

RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'
CYN='\033[0;36m'; BLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'
ok()   { printf "  ${GRN}✓${RST}  %s\n" "$*"; }
warn() { printf "  ${YEL}⚠${RST}  %s\n" "$*"; }
err()  { printf "  ${RED}✗${RST}  %s\n" "$*"; }
info() { printf "  ${DIM}·${RST}  %s\n" "$*"; }
hdr()  { printf "\n${BLD}${CYN}▶ %s${RST}\n" "$*"; }
sep()  { printf '%s\n' "────────────────────────────────────────────────────"; }

# ── JSON comment stripper ─────────────────────────────────────────────────────
strip_jsonc() {
    python3 - "$1" << 'PYEOF'
import sys, json
def strip(text):
    r=[]; in_s=False; i=0
    while i<len(text):
        c=text[i]
        if c=='"' and (i==0 or text[i-1]!='\\'): in_s=not in_s
        if not in_s and c=='/' and i+1<len(text) and text[i+1]=='/':
            while i<len(text) and text[i]!='\n': i+=1
            continue
        r.append(c); i+=1
    return ''.join(r)
with open(sys.argv[1]) as f: raw=f.read()
print(json.dumps(json.loads(strip(raw))))
PYEOF
}

# ════════════════════════════════════════════════════════════════════════════════
# STATIC: CSS
# ════════════════════════════════════════════════════════════════════════════════

check_css() {
    local css_file="$1"
    local issues=0

    [[ -f "$css_file" ]] || { err "style.css missing"; return 1; }

    # Brace balance
    local opens closes
    opens=$(grep -o '{' "$css_file" | wc -l)
    closes=$(grep -o '}' "$css_file" | wc -l)
    if [[ "$opens" -ne "$closes" ]]; then
        err "Unbalanced braces: $opens open, $closes close"
        ((issues++))
    else
        ok "Braces balanced ($opens pairs)"
    fi

    # Combined keyframe selectors  — "0%, 100% { }" kills GTK CSS parser
    if grep -qE '0%\s*,\s*100%' "$css_file" 2>/dev/null; then
        local ln; ln=$(grep -nE '0%\s*,\s*100%' "$css_file" | head -1)
        err "Combined keyframe selector: $ln"
        err "  Fix: split into 0% { } ... 50% { } ... 100% { }"
        ((issues++))
    else
        ok "No combined keyframe selectors"
    fi

    # transform inside @keyframes — kills GTK CSS parser
    local kf_issue
    kf_issue=$(python3 - "$css_file" << 'PYEOF' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
for m in re.finditer(r'@keyframes\s+\w+\s*\{', content):
    start = m.start(); depth = 0
    for i in range(start, len(content)):
        if content[i]=='{': depth+=1
        elif content[i]=='}':
            depth-=1
            if depth==0:
                chunk=content[start:i+1]
                if 'transform' in chunk:
                    print(f"line {content[:start].count(chr(10))+1}")
                break
PYEOF
    )
    if [[ -n "$kf_issue" ]]; then
        err "transform inside @keyframes at $kf_issue — GTK CSS does not support this"
        err "  Fix: remove transform from keyframe, apply it in base selector"
        ((issues++))
    else
        ok "No transform in @keyframes"
    fi

    # Invalid properties
    for prop in '-gtk-icon-effect' 'backdrop-filter'; do
        if grep -q "$prop" "$css_file" 2>/dev/null; then
            err "$prop found — crashes GTK CSS parser"
            ((issues++))
        else
            ok "No $prop"
        fi
    done

    # CSS custom properties
    if grep -qE 'var\(--' "$css_file" 2>/dev/null; then
        local ln; ln=$(grep -nE 'var\(--' "$css_file" | head -1)
        err "CSS var(--) at $ln — not supported in GTK CSS"
        err "  Fix: use @color_name or rgba() directly"
        ((issues++))
    else
        ok "No CSS var() custom properties"
    fi

    # filter: property
    if grep -qE '^\s*filter\s*:' "$css_file" 2>/dev/null; then
        err "filter: property not supported by GTK CSS"
        ((issues++))
    else
        ok "No filter: property"
    fi

    # Check active CSS (strip comments first) for invisible-bar crash patterns
    local css_no_comments
    css_no_comments=$(python3 -c "
import re, sys
c = open('$css_file').read()
c = re.sub(r'/[*].*?[*]/', '', c, flags=re.DOTALL)
c = re.sub(r'//[^\n]*', '', c)
print(c)
" 2>/dev/null || cat "$css_file")

    # max-width: crashes GTK CSS layout silently — every broken preset had this, no working one did
    if printf '%s' "$css_no_comments" | grep -qE '\bmax-width\s*:'; then
        local ln; ln=$(grep -n 'max-width' "$css_file" | grep -v '/\*' | head -1)
        err "max-width at $ln — not supported in GTK CSS, causes invisible bar"
        err "  Fix: remove max-width entirely"
        ((issues++))
    else
        ok "No max-width"
    fi

    # border-top/bottom/left/right shorthand: not supported in GTK CSS
    if printf '%s' "$css_no_comments" | grep -qE 'border-(top|bottom|left|right)\s*:\s*[0-9]'; then
        local ln; ln=$(grep -nE 'border-(top|bottom|left|right)\s*:' "$css_file" | grep -v '/\*' | head -1)
        err "Directional border shorthand at $ln — GTK CSS only supports 'border:' not 'border-side:'"
        err "  Fix: remove these lines"
        ((issues++))
    else
        ok "No directional border shorthand"
    fi

    # standalone border-color: must be part of border: shorthand in GTK CSS
    if printf '%s' "$css_no_comments" | grep -qE '^\s*border-color\s*:'; then
        local ln; ln=$(grep -n 'border-color\s*:' "$css_file" | grep -v '/\*' | head -1)
        err "Standalone border-color at $ln — use 'border: 1px solid <color>' instead"
        ((issues++))
    else
        ok "No standalone border-color"
    fi

    # Box shadow
    # Box shadow
    if ! grep -q 'box-shadow:\s*none' "$css_file" 2>/dev/null; then
        warn "No 'box-shadow: none' — GTK theme may inject a shadow making bar look boxy"
    else
        ok "box-shadow: none present"
    fi

    # @import path check
    local import_path
    import_path=$(grep '@import' "$css_file" 2>/dev/null | grep -oP '(?<=@import ").*(?=")' | head -1 || echo "")
    if [[ -n "$import_path" ]]; then
        if [[ -f "$import_path" ]]; then
            ok "@import exists: $import_path"
            # Validate GTK @define-color format
            if grep -q '@define-color' "$import_path" 2>/dev/null; then
                local color_count
                color_count=$(grep -c '@define-color' "$import_path" 2>/dev/null || echo 0)
                ok "  Color file has $color_count @define-color entries"
            else
                warn "  Color file doesn't contain @define-color entries"
                warn "  If it uses CSS :root { --vars } format, @colorname refs will fail"
                warn "  → All module colors would resolve to transparent = invisible bar"
            fi
        else
            err "@import file missing: $import_path"
            err "  Fix: run matugen to generate colors, or update the path in style.css"
            err "  Until fixed, ALL color references will fail = bar is invisible"
            ((issues++))
        fi
    else
        info "No @import (using raw rgba/hex — always safe)"
    fi

    # Font
    local font
    font=$(grep -oP "font-family:\s*'?\K[^';,\n]+" "$css_file" 2>/dev/null | head -1 | xargs || echo "")
    if [[ -n "$font" ]]; then
        if fc-list 2>/dev/null | grep -qi "$font"; then
            ok "Font '$font' installed"
        else
            warn "Font '$font' not found by fc-list"
            warn "  Bar will use a fallback font — text renders but looks different"
        fi
    fi

    return $issues
}

# ════════════════════════════════════════════════════════════════════════════════
# STATIC: CONFIG
# ════════════════════════════════════════════════════════════════════════════════

check_config() {
    local config_file="$1"
    local issues=0

    [[ -f "$config_file" ]] || { err "config.jsonc missing"; return 1; }

    local parsed
    if ! parsed=$(strip_jsonc "$config_file" 2>&1); then
        err "JSON parse failed: $parsed"
        err "  Fix: check for trailing commas, missing quotes, mismatched brackets"
        return 1
    fi

    # Position
    local pos
    pos=$(printf '%s' "$parsed" | python3 -c "import json,sys; c=json.load(sys.stdin); print(c.get('position','top'))")
    ok "position: $pos"

    local is_vertical=false
    [[ "$pos" == "left" || "$pos" == "right" ]] && is_vertical=true

    # Size
    local width height
    width=$(printf '%s' "$parsed" | python3 -c "import json,sys; c=json.load(sys.stdin); print(c.get('width',''))")
    height=$(printf '%s' "$parsed" | python3 -c "import json,sys; c=json.load(sys.stdin); print(c.get('height',''))")

    if $is_vertical; then
        [[ -n "$width" ]] && ok "width: ${width}px" || warn "No width set for vertical bar — may be very wide"
    else
        [[ -n "$height" ]] && ok "height: ${height}px" || warn "No height set"
    fi

    # Modules
    local mod_count
    mod_count=$(printf '%s' "$parsed" | python3 -c "
import json, sys
c = json.load(sys.stdin)
mods = c.get('modules-left',[]) + c.get('modules-center',[]) + c.get('modules-right',[])
print(len(mods))
")
    [[ "$mod_count" -gt 0 ]] && ok "$mod_count modules defined" || { err "No modules"; ((issues++)); }

    # Custom module config blocks
    local missing_blocks
    missing_blocks=$(printf '%s' "$parsed" | python3 -c "
import json, sys
c = json.load(sys.stdin)
mods = c.get('modules-left',[]) + c.get('modules-center',[]) + c.get('modules-right',[])
for m in mods:
    if not m.startswith('custom/'): continue
    base = m.split('#')[0]
    if m not in c and base not in c:
        print(m)
" 2>/dev/null)
    if [[ -n "$missing_blocks" ]]; then
        while IFS= read -r mod; do
            err "Custom module '$mod' has no config block"
            ((issues++))
        done <<< "$missing_blocks"
    else
        ok "All custom modules have config blocks"
    fi

    # Output key
    local output
    output=$(printf '%s' "$parsed" | python3 -c "import json,sys; c=json.load(sys.stdin); print(c.get('output',''))")
    if [[ -n "$output" && "$output" != "None" ]]; then
        warn "output: '$output' — bar only shows on this monitor. Wrong name = invisible bar"
    else
        ok "output: all monitors"
    fi

    return $issues
}

# ════════════════════════════════════════════════════════════════════════════════
# STATIC: SCRIPTS
# ════════════════════════════════════════════════════════════════════════════════

check_scripts() {
    local config_file="$1"
    local issues=0

    local scripts
    scripts=$(python3 - "$config_file" << 'PYEOF' 2>/dev/null
import json, re, sys, os
def strip(text):
    r=[]; in_s=False; i=0
    while i<len(text):
        c=text[i]
        if c=='"' and (i==0 or text[i-1]!='\\'): in_s=not in_s
        if not in_s and c=='/' and i+1<len(text) and text[i+1]=='/':
            while i<len(text) and text[i]!='\n': i+=1
            continue
        r.append(c); i+=1
    return ''.join(r)
try:
    cfg = json.loads(strip(open(sys.argv[1]).read()))
    home = os.environ.get('HOME', '')
    seen = set()
    for key, block in cfg.items():
        if not isinstance(block, dict): continue
        for field in ('exec', 'exec-if'):
            val = block.get(field, '')
            if not val: continue
            path = val.split()[0].replace('~', home)
            if path.startswith('/') and path not in seen:
                seen.add(path)
                print(path)
except Exception: pass
PYEOF
    )

    if [[ -z "$scripts" ]]; then
        info "No local script exec paths to verify"
        return 0
    fi

    while IFS= read -r script; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                ok "Script OK: $(basename "$script")"
            else
                warn "Not executable: $(basename "$script")"
                warn "  Fix: chmod +x $script"
            fi
        else
            err "Script missing: $script"
            ((issues++))
        fi
    done <<< "$scripts"

    return $issues
}

# ════════════════════════════════════════════════════════════════════════════════
# STATIC: FULL PRESET
# ════════════════════════════════════════════════════════════════════════════════

diagnose_preset() {
    local name="$1" dir="$2"
    local total=0

    sep
    printf "${BLD}Preset: %-30s${RST}\n" "$name"
    sep

    hdr "config.jsonc"
    check_config "${dir}/config.jsonc" || ((total += $?)) || true

    hdr "style.css"
    check_css "${dir}/style.css" || ((total += $?)) || true

    hdr "Scripts"
    check_scripts "${dir}/config.jsonc" || ((total += $?)) || true

    if [[ $total -eq 0 ]]; then
        printf "\n  ${GRN}${BLD}✓ %s — no issues${RST}\n" "$name"
    else
        printf "\n  ${RED}${BLD}✗ %s — %d issue(s)${RST}\n" "$name" "$total"
    fi
    return $total
}

# ════════════════════════════════════════════════════════════════════════════════
# RUNTIME: TEST ONE PRESET
# ════════════════════════════════════════════════════════════════════════════════

runtime_test() {
    local preset="$1"
    local preset_dir="${PRESETS_DIR}/${preset}"

    [[ -d "$preset_dir" ]] || { err "Preset not found: $preset_dir"; return 1; }
    [[ -x "$SWITCH_SCRIPT" ]] || { err "switch_style.sh not found: $SWITCH_SCRIPT"; return 1; }
    [[ -x "$LAUNCH_SCRIPT" ]] || { err "launch_waybar.sh not found: $LAUNCH_SCRIPT"; return 1; }

    local original
    original="$(cat "$CURRENT_PRESET_FILE" 2>/dev/null || echo "")"

    sep
    printf "${BLD}Runtime test: %s${RST}\n" "$preset"
    sep

    # Timestamp before switch
    local before; before=$(date +%s)

    info "Switching to $preset..."
    "$SWITCH_SCRIPT" "$preset" 2>/dev/null || { err "switch_style.sh failed"; return 1; }
    "$LAUNCH_SCRIPT" 2>/dev/null &
    local lpid=$!

    info "Waiting 4s for waybar to initialise..."
    sleep 4

    # ── 1. Process check ──────────────────────────────────────────────────────
    hdr "Process"
    local pids; pids=$(pgrep -x waybar 2>/dev/null || echo "")
    local pcnt=0; [[ -n "$pids" ]] && pcnt=$(printf '%s' "$pids" | wc -l | tr -d ' ')

    if [[ $pcnt -eq 0 ]]; then
        err "waybar NOT running — crashed immediately"
        err "  → CSS or config error. Check --log for the crash line."
    elif [[ $pcnt -eq 1 ]]; then
        ok "waybar running (PID: $pids)"
    else
        warn "$pcnt waybar instances running (PIDs: $pids)"
        warn "  → Stale instances. Fix: killall waybar && $LAUNCH_SCRIPT"
    fi

    # ── 2. Journal for this run ───────────────────────────────────────────────
    hdr "Journal (this run)"
    local logs
    logs=$(journalctl --user -u "waybar-mgr-*" --since "@${before}" --no-pager 2>/dev/null || \
           journalctl --user -u "waybar*" --since "@${before}" --no-pager 2>/dev/null || echo "")

    if [[ -z "$logs" ]]; then
        warn "No journal output found — check: journalctl --user -u 'waybar*' -n 20"
    else
        # CSS crash
        if printf '%s' "$logs" | grep -q 'Expected closing bracket'; then
            local lineno; lineno=$(printf '%s' "$logs" | grep -oP 'style\.css:\K\d+' | head -1)
            err "CSS CRASH at style.css line ${lineno:-?}: Expected closing bracket after keyframes"
            err "  Cause: combined keyframe 0%%,100%% or transform in @keyframes"
        fi

        # Other errors
        printf '%s' "$logs" | grep -iE '\[error\]' | while IFS= read -r line; do err "$line"; done

        # Success
        if printf '%s' "$logs" | grep -q 'Bar configured'; then
            local bar_line; bar_line=$(printf '%s' "$logs" | grep 'Bar configured' | tail -1)
            ok "$bar_line"
            printf "\n"
            printf "  ${BLD}Bar started. If you can${RST}'${BLD}t see it:${RST}\n"
            printf "  ${CYN}1.${RST} Check the edge — is another window or panel covering it?\n"
            printf "  ${CYN}2.${RST} Colors all transparent? Verify matugen colors file:\n"
            printf "       head -5 %s\n" "$(grep '@import' "${preset_dir}/style.css" 2>/dev/null | grep -oP '(?<=@import ").*(?=")' | head -1)"
            printf "  ${CYN}3.${RST} Font missing? Run: fc-list | grep -i monocraft\n"
            printf "  ${CYN}4.${RST} Wrong monitor edge? Check position in config.jsonc.\n"
        elif [[ $pcnt -eq 0 ]]; then
            err "Bar never configured — check --log for more detail"
        fi

        # Height warning
        if printf '%s' "$logs" | grep -q 'less than the minimum height'; then
            warn "$(printf '%s' "$logs" | grep 'less than the minimum height' | tail -1)"
        fi
    fi

    # ── 3. Hyprland layer check ───────────────────────────────────────────────
    hdr "Hyprland layers"
    if command -v hyprctl &>/dev/null; then
        local layer_info
        layer_info=$(hyprctl layers 2>/dev/null | grep -i waybar || echo "")
        if [[ -n "$layer_info" ]]; then
            ok "waybar is registered as a layer surface (correct)"
            printf '%s\n' "$layer_info" | while IFS= read -r l; do info "  $l"; done
        else
            warn "waybar not found in Hyprland layer surfaces"
            [[ $pcnt -gt 0 ]] && warn "  Process exists but Hyprland doesn't see it — may have wrong XDG_RUNTIME_DIR"
        fi
    else
        info "hyprctl unavailable"
    fi

    # ── Restore ───────────────────────────────────────────────────────────────
    if [[ -n "$original" && "$original" != "$preset" ]]; then
        printf "\n  Restoring: %s\n" "$original"
        "$SWITCH_SCRIPT" "$original" 2>/dev/null
        "$LAUNCH_SCRIPT" 2>/dev/null &
        sleep 2
    fi

    wait "$lpid" 2>/dev/null || true
}

# ════════════════════════════════════════════════════════════════════════════════
# PROCESS CHECK
# ════════════════════════════════════════════════════════════════════════════════

check_processes() {
    hdr "Waybar processes"
    local pids; pids=$(pgrep -x waybar 2>/dev/null || echo "")

    if [[ -z "$pids" ]]; then
        warn "waybar is not running"
    else
        local cnt; cnt=$(printf '%s' "$pids" | wc -l | tr -d ' ')
        if [[ $cnt -eq 1 ]]; then
            ok "1 waybar process (PID: $pids)"
        else
            err "$cnt waybar processes — stale instances will cause display conflicts"
            err "  Fix: killall waybar && sleep 1 && $LAUNCH_SCRIPT"
        fi
        for pid in $pids; do
            local stat; stat=$(ps -p "$pid" -o pid,pcpu,pmem,etime --no-headers 2>/dev/null || echo "")
            [[ -n "$stat" ]] && info "$stat"
        done
    fi

    hdr "Active preset"
    local current; current="$(cat "$CURRENT_PRESET_FILE" 2>/dev/null || echo "(none)")"
    info "Current: $current"
    [[ -d "${PRESETS_DIR}/${current}" ]] && ok "Preset directory exists" || \
        { [[ "$current" != "(none)" ]] && err "Preset directory missing: ${PRESETS_DIR}/${current}"; }
}

# ════════════════════════════════════════════════════════════════════════════════
# LOG VIEWER
# ════════════════════════════════════════════════════════════════════════════════

show_logs() {
    hdr "Recent waybar logs"
    sep
    journalctl --user -u "waybar-mgr-*" -n 60 --no-pager 2>/dev/null || \
    journalctl --user -u "waybar*" -n 60 --no-pager 2>/dev/null || \
    warn "No waybar journal entries found"

    hdr "Error summary"
    local logs
    logs=$(journalctl --user -u "waybar*" -n 200 --no-pager 2>/dev/null || echo "")

    if printf '%s' "$logs" | grep -q 'Expected closing bracket'; then
        err "CRASH PATTERN: CSS keyframes parse error"
        printf '%s' "$logs" | grep 'Expected closing bracket' | while IFS= read -r l; do err "  $l"; done
        printf "  ${YEL}Cause:${RST} 0%%,100%% combined selector or transform in @keyframes\n"
    fi

    if printf '%s' "$logs" | grep -q 'Bar configured'; then
        ok "Last successful start:"
        printf '%s' "$logs" | grep 'Bar configured' | tail -3 | while IFS= read -r l; do info "  $l"; done
    else
        warn "No successful 'Bar configured' in recent logs"
    fi

    if printf '%s' "$logs" | grep -qE 'exit-code|FAILURE'; then
        err "Recent failure:"
        printf '%s' "$logs" | grep -E 'exit-code|FAILURE' | tail -3 | while IFS= read -r l; do err "  $l"; done
    fi
}

# ════════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════════

printf "${BLD}${CYN}╔═══════════════════════════════════════════════════╗\n"
printf "║  Waybar Debug Tool v2                             ║\n"
printf "╚═══════════════════════════════════════════════════╝${RST}\n"

case "${1:-}" in
    --log)        show_logs ;;
    --processes)  check_processes ;;
    --watch)
        hdr "Live log stream (Ctrl+C to stop)"
        journalctl --user -u "waybar*" -f --no-pager
        ;;
    --test)
        [[ -n "${2:-}" ]] || { err "Usage: $0 --test <preset>"; exit 1; }
        runtime_test "$2"
        ;;
    --test-all)
        [[ -d "$PRESETS_DIR" ]] || { err "Presets dir not found: $PRESETS_DIR"; exit 1; }
        p=0; f=0
        for dir in "$PRESETS_DIR"/*/; do
            [[ -d "$dir" ]] || continue
            name="$(basename "$dir")"
            runtime_test "$name" && ((p++)) || ((f++))
            sleep 3
        done
        sep
        printf "\n${BLD}Results: ${GRN}%d passed${RST} / ${RED}%d failed${RST}\n\n" "$p" "$f"
        ;;
    --live)
        hdr "Diagnosing active deployed config"
        current="$(cat "$CURRENT_PRESET_FILE" 2>/dev/null || echo "unknown")"
        info "Active: $current"
        tmp=$(mktemp -d)
        cp "$ACTIVE_CONFIG" "$tmp/config.jsonc"
        cp "$ACTIVE_STYLE"  "$tmp/style.css"
        diagnose_preset "LIVE ($current)" "$tmp"
        ec=$?; rm -rf "$tmp"; exit $ec
        ;;
    "")
        [[ -d "$PRESETS_DIR" ]] || { err "Presets dir not found: $PRESETS_DIR"; exit 1; }
        check_processes
        total=0; failed=0; failed_names=()
        for dir in "$PRESETS_DIR"/*/; do
            [[ -d "$dir" ]] || continue
            name="$(basename "$dir")"
            ((total++))
            diagnose_preset "$name" "$dir" || { ((failed++)); failed_names+=("$name"); }
        done
        sep
        printf "\n${BLD}%d presets scanned${RST}\n" "$total"
        if [[ $failed -eq 0 ]]; then
            printf "${GRN}${BLD}All clean.${RST}\n"
        else
            printf "${RED}${BLD}%d with issues:${RST}\n" "$failed"
            for n in "${failed_names[@]}"; do printf "  ${RED}•${RST} %s\n" "$n"; done
        fi
        printf "\n${DIM}If static checks pass but bars are invisible, run:${RST}\n"
        printf "  ${CYN}%s --test <preset>${RST}   switch + watch live logs\n" "$0"
        printf "  ${CYN}%s --log${RST}             parse recent crash history\n" "$0"
        printf "  ${CYN}%s --processes${RST}        check for stale waybar instances\n\n" "$0"
        ;;
    *)
        name="$1"
        dir="${PRESETS_DIR}/${name}"
        if [[ ! -d "$dir" ]]; then
            err "Preset not found: $dir"
            printf "\nAvailable:\n"
            for d in "$PRESETS_DIR"/*/; do printf "  • %s\n" "$(basename "$d")"; done
            exit 1
        fi
        diagnose_preset "$name" "$dir"
        printf "\n${DIM}Runtime-test: %s --test %s${RST}\n\n" "$0" "$name"
        exit $?
        ;;
esac
