#!/usr/bin/env bash
# Package manager helpers for Command Center (replaces rofi/packages.sh menus).
set -euo pipefail

PROTECTED=(
    base base-devel linux linux-headers linux-firmware
    systemd bash glibc pacman sudo
    hyprland rofi kitty networkmanager
    grub efibootmgr mesa xorg-server wayland
)

detect_pm() {
    if command -v yay &>/dev/null; then echo "yay"
    elif command -v paru &>/dev/null; then echo "paru"
    elif command -v pacman &>/dev/null; then echo "pacman"
    else echo ""; fi
}

is_protected() {
    local pkg="$1" p
    for p in "${PROTECTED[@]}"; do
        [[ "$pkg" == "$p" ]] && return 0
    done
    return 1
}

list_packages() {
    local filter="$1"
    local pm
    pm="$(detect_pm)"
    [[ -n "$pm" ]] || exit 0

    local raw
    if [[ "$filter" == "explicit" ]]; then
        raw="$(pacman -Qe 2>/dev/null | awk '{print $1}')"
    else
        raw="$(pacman -Q 2>/dev/null | awk '{print $1}')"
    fi
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] || [[ "$pkg" == *" "* ]] && continue
        if [[ "$filter" == "explicit" ]]; then
            is_protected "$pkg" && continue
        fi
        jq -cn --arg name "$pkg" --arg pm "$pm" '{name:$name,pm:$pm}'
    done <<<"$raw"
}

run_remove() {
    local pkg="$1"
    local pm qpkg
    pm="$(detect_pm)"
    [[ -n "$pm" && -n "$pkg" ]] || exit 1
    is_protected "$pkg" && exit 1
    qpkg=$(printf '%q' "$pkg")
    if [[ "$pm" == "pacman" ]]; then
        kitty -e sh -c "sudo pacman -Rns ${qpkg}; echo; read -rp 'Press Enter to close '" &
    else
        kitty -e sh -c "${pm} -Rns ${qpkg}; echo; read -rp 'Press Enter to close '" &
    fi
}

run_info() {
    local pkg="$1"
    local pm qpkg
    pm="$(detect_pm)"
    [[ -n "$pm" && -n "$pkg" ]] || exit 1
    qpkg=$(printf '%q' "$pkg")
    if [[ "$pm" == "pacman" ]]; then
        kitty -e sh -c "pacman -Qi ${qpkg}; echo; read -rp 'Press Enter to close '" &
    else
        kitty -e sh -c "${pm} -Qi ${qpkg}; echo; read -rp 'Press Enter to close '" &
    fi
}

cmd="${1:-}"
case "$cmd" in
    pm) detect_pm ;;
    list) list_packages "${2:-all}" ;;
    remove) run_remove "${2:-}" ;;
    info) run_info "${2:-}" ;;
    *)
        echo "usage: packages-ctl.sh {pm|list explicit|all|remove PKG|info PKG}" >&2
        exit 1
        ;;
esac
