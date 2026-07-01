#!/usr/bin/env bash
# =============================================================================
# packages.sh — Package Manager Menu (yay / paru / pacman)
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# =============================================================================
# HELPERS
# =============================================================================

# Packages that must never be removed via this UI
readonly -a PROTECTED_PACKAGES=(
    base base-devel linux linux-headers linux-firmware
    systemd bash glibc pacman sudo
    hyprland rofi kitty networkmanager
    grub efibootmgr mesa xorg-server wayland
)

detect_pkg_manager() {
    if command -v yay  &>/dev/null; then echo "yay"
    elif command -v paru &>/dev/null; then echo "paru"
    elif command -v pacman &>/dev/null; then echo "pacman"
    else
        notify-send "Error" "No supported package manager found"
        return 1
    fi
}

# Returns newline-separated list of all installed package names
get_pkg_list() {
    local pm="$1"
    if [[ "$pm" == "pacman" ]]; then
        pacman -Q | awk '{print $1}'
    else
        "$pm" -Q | awk '{print $1}'
    fi
}

# Returns only explicitly installed packages
get_explicit_pkg_list() {
    local pm="$1"
    if [[ "$pm" == "pacman" ]]; then
        pacman -Qe | awk '{print $1}'
    else
        "$pm" -Qe | awk '{print $1}'
    fi
}

is_protected() {
    local pkg="$1"
    for p in "${PROTECTED_PACKAGES[@]}"; do
        [[ "$pkg" == "$p" ]] && return 0
    done
    return 1
}

# =============================================================================
# REMOVE PACKAGE
# =============================================================================

remove_package() {
    local pm
    pm=$(detect_pkg_manager) || { show_package_menu; return; }

    local raw_list
    raw_list=$(get_explicit_pkg_list "$pm")
    local total
    total=$(wc -l <<<"$raw_list")

    # Filter out protected packages
    local filtered_list=""
    while IFS= read -r pkg; do
        is_protected "$pkg" || filtered_list+="${pkg}\n"
    done <<<"$raw_list"

    local selected_pkg
    selected_pkg=$(printf "%b" "$filtered_list" | rofi -dmenu -i \
        -p "Remove Package" \
        -theme-str 'window { width: 50%; }' \
        -theme-str 'listview { lines: 15; }' \
        -mesg "${total} packages installed | Protected: ${#PROTECTED_PACKAGES[@]}") || true

    [[ -z "$selected_pkg" ]] && { show_package_menu; return; }

    # Confirmation step
    local confirm
    confirm=$(centered_menu "Remove ${selected_pkg}?" \
        "󰆴 Confirm Removal\n󰸉 Cancel") || true

    case "$confirm" in
        *"Confirm"*)
            if [[ "$pm" == "pacman" ]]; then
                kitty -e sh -c "sudo pacman -Rns ${selected_pkg}; read -p 'Press Enter to close'" &
            else
                kitty -e sh -c "${pm} -Rns ${selected_pkg}; read -p 'Press Enter to close'" &
            fi
            ;;
        *)
            show_package_menu
            ;;
    esac
}

# =============================================================================
# PACKAGE INFO
# =============================================================================

package_info() {
    local pm
    pm=$(detect_pkg_manager) || { show_package_menu; return; }

    local pkg_list
    pkg_list=$(get_pkg_list "$pm")

    local selected_pkg
    selected_pkg=$(echo "$pkg_list" | rofi -dmenu -i \
        -p "Package Info" \
        -theme-str 'window { width: 50%; }' \
        -theme-str 'listview { lines: 15; }') || true

    [[ -z "$selected_pkg" ]] && { show_package_menu; return; }

    if command -v kitty &>/dev/null; then
        if [[ "$pm" == "pacman" ]]; then
            kitty -e sh -c "pacman -Qi ${selected_pkg}; read -p 'Press Enter to close'" &
        else
            kitty -e sh -c "${pm} -Qi ${selected_pkg}; read -p 'Press Enter to close'" &
        fi
    fi
}

# =============================================================================
# PACKAGE MENU
# =============================================================================

show_package_menu() {
    local choice
    choice=$(menu "Packages" \
        "󰆴 Remove Package\n󰋼 Package Info\n󰘍 Back") || true

    case "$choice" in
        *"Remove Package"*) remove_package ;;
        *"Package Info"*)   package_info ;;
        *"Back"*)           back_to_main ;;
        *)                  back_to_main ;;
    esac
}

# =============================================================================
# ENTRY POINT
# =============================================================================

show_package_menu
