#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# reload_sliders.sh
# Manages the cloudyy_sliders.py daemon lifecycle:
#   1. Terminates any running instance (SIGTERM → SIGKILL)
#   2. Resets systemd failure state
#   3. Starts a clean systemd user service instance
#   4. Signals the UI to show via D-Bus (unless --quiet)
#
# Usage:
#   reload_sliders.sh           → restart + show window
#   reload_sliders.sh --quiet   → restart only (no window activation)
# -----------------------------------------------------------------------------

set -euo pipefail
trap '' HUP

# ── Config ────────────────────────────────────────────────────────────────────
readonly SERVICE_NAME="cloudyy_sliders.service"
readonly PROCESS_PATTERN='cloudyy_sliders\.py'
readonly GUI_SCRIPT="${HOME}/user_scripts/sliders/cloudyy_sliders.py"
readonly SELF_PID=$$

# Timing
readonly GRACE_LOOPS=20
readonly GRACE_SLEEP=0.1
readonly POST_KILL_SETTLE=0.2
readonly SERVICE_INIT_DELAY=0.3
readonly DBUS_WAIT=1.0

# ── Colours (TTY only) ────────────────────────────────────────────────────────
if [[ -t 1 && -t 2 ]]; then
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

log_info() { printf '%s[INFO]%s %s\n'    "${C_BLUE}"   "${C_RESET}" "$*"; }
log_ok()   { printf '%s[ OK ]%s %s\n'   "${C_GREEN}"  "${C_RESET}" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n'   "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_err()  { printf '%s[ ERR]%s %s\n'   "${C_RED}"    "${C_RESET}" "$*" >&2; }

# ── Preflight ─────────────────────────────────────────────────────────────────
preflight() {
    ((EUID != 0)) || { log_err "Do not run as root."; return 1; }
    local missing=()
    for cmd in pgrep systemctl journalctl python3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    ((${#missing[@]} == 0)) || { log_err "Missing: ${missing[*]}"; return 1; }
}

# ── Process management ────────────────────────────────────────────────────────
get_pids() {
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] && ((pid != SELF_PID)) && printf '%s\n' "$pid"
    done < <(pgrep -f -- "$PROCESS_PATTERN" 2>/dev/null || true)
}

terminate() {
    (($# > 0)) || return 0
    local -a pids=("$@")
    log_info "Terminating PIDs: ${pids[*]}"

    for pid in "${pids[@]}"; do kill -TERM -- "$pid" 2>/dev/null || true; done

    local i
    for ((i = 0; i < GRACE_LOOPS; i++)); do
        local alive=0
        for pid in "${pids[@]}"; do kill -0 -- "$pid" 2>/dev/null && alive=1 && break; done
        ((alive)) || { log_ok "Terminated gracefully."; return 0; }
        sleep "$GRACE_SLEEP"
    done

    log_warn "Grace period exceeded — sending SIGKILL."
    for pid in "${pids[@]}"; do kill -KILL -- "$pid" 2>/dev/null || true; done
    sleep "$POST_KILL_SETTLE"
    log_ok "Force-killed."
}

# ── Service management ────────────────────────────────────────────────────────
start_service() {
    log_info "Starting ${C_BOLD}${SERVICE_NAME}${C_RESET}..."
    systemctl --user reset-failed -- "$SERVICE_NAME" 2>/dev/null || true

    if ! systemctl --user start -- "$SERVICE_NAME"; then
        log_err "systemctl start failed. Recent logs:"
        journalctl --user -u "$SERVICE_NAME" -n 15 --no-pager >&2
        return 1
    fi

    sleep "$SERVICE_INIT_DELAY"

    if ! systemctl --user is-active --quiet -- "$SERVICE_NAME"; then
        log_err "Service exited immediately. Recent logs:"
        journalctl --user -u "$SERVICE_NAME" -n 10 --no-pager >&2
        return 1
    fi

    log_ok "Service is active."
}

# ── UI activation ─────────────────────────────────────────────────────────────
activate_ui() {
    [[ -f "$GUI_SCRIPT" ]] || { log_warn "Script not found: $GUI_SCRIPT"; return 0; }
    log_info "Activating window via D-Bus (waiting ${DBUS_WAIT}s for registration)..."
    sleep "$DBUS_WAIT"
    # Running the script again sends an activate signal to the live daemon; it exits instantly.
    if [[ -x "$GUI_SCRIPT" ]]; then
        "$GUI_SCRIPT" >/dev/null 2>&1 &
    else
        python3 -- "$GUI_SCRIPT" >/dev/null 2>&1 &
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    local quiet=0
    while (($# > 0)); do
        case "$1" in
            -q|--quiet) quiet=1 ;;
        esac
        shift
    done

    preflight || return 1

    log_info "Restarting ${C_BOLD}Cloudyy Sliders${C_RESET}..."

    local -a pids
    mapfile -t pids < <(get_pids)
    ((${#pids[@]} > 0)) && terminate "${pids[@]}" || log_info "No existing instances."

    start_service || return 1

    if ((quiet == 0)); then
        activate_ui
    else
        log_info "Quiet mode — skipping UI activation."
    fi

    log_ok "Done."
}

main "$@"
