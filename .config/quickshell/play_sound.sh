#!/usr/bin/env bash
# Play UI sounds from ~/.config/quickshell/sounds/
# Usage: play_sound.sh <notif|screencap> [delay_ms]
set -uo pipefail

readonly SOUNDS_DIR="${CLOUDYY_SOUNDS_DIR:-${HOME}/.config/quickshell/sounds}"

resolve_sound() {
    case "${1:-}" in
        notif)    echo "${SOUNDS_DIR}/NotifSOUND.wav" ;;
        screencap) echo "${SOUNDS_DIR}/SCRNCAP_SOUND.wav" ;;
        *) return 1 ;;
    esac
}

play_file() {
    local file=$1

    if command -v paplay >/dev/null 2>&1; then
        paplay "$file" 2>/dev/null && return 0
    fi
    if command -v ffplay >/dev/null 2>&1; then
        ffplay -nodisp -autoexit -loglevel quiet "$file" 2>/dev/null && return 0
    fi
    if command -v mpv >/dev/null 2>&1; then
        mpv --no-video --really-quiet "$file" 2>/dev/null && return 0
    fi
    return 1
}

main() {
    local kind=${1:-}
    local delay_ms=${2:-0}
    local file

    file=$(resolve_sound "$kind") || exit 0
    [[ -f "$file" ]] || exit 0

    if [[ "$delay_ms" =~ ^[0-9]+$ ]] && [[ "$delay_ms" -gt 0 ]]; then
        sleep "$(awk "BEGIN { printf \"%.3f\", ${delay_ms}/1000 }")"
    fi

    play_file "$file" || true
}

main "$@"
