#!/usr/bin/env bash
# Attach to the installed terminal multiplexer when Cloud Center autostart is on.
# Prefers zellij over tmux (matches SWAPPABLE_MULTIPLEXER in dependencies.conf).

set -euo pipefail

readonly SETTINGS_DIR="${HOME}/.config/cloud-center/settings/terminal"

_cc_autostart_enabled() {
    local file value
    for file in multiplexer_autostart tmux_autostart; do
        if [[ -f "${SETTINGS_DIR}/${file}" ]]; then
            value="$(tr '[:upper:]' '[:lower:]' < "${SETTINGS_DIR}/${file}")"
            [[ "$value" == "true" ]] && return 0
            return 1
        fi
    done
    return 1
}

_detect_multiplexer() {
    if command -v zellij &>/dev/null; then
        echo zellij
    elif command -v tmux &>/dev/null; then
        echo tmux
    else
        echo none
    fi
}

# Already inside a multiplexer session
if [[ -n "${TMUX:-}" || -n "${ZELLIJ:-}" ]]; then
    exit 0
fi

_cc_autostart_enabled || exit 0

case "$(_detect_multiplexer)" in
    zellij)
        exec zellij attach -c default
        ;;
    tmux)
        exec tmux attach-session -t default 2>/dev/null || exec tmux new-session -s default
        ;;
    *)
        exit 0
        ;;
esac
