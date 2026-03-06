#!/usr/bin/env bash
# =============================================================================
# hyprland-install.sh — Interactive Package Installer for cloudyy-linux
# =============================================================================
# Run standalone or called from install.sh.
# Reads dependencies.conf for all package definitions.
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPS_FILE="${SCRIPT_DIR}/dependencies.conf"

# --- Colors ------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED=$'\e[1;31m'  GREEN=$'\e[1;32m'  YELLOW=$'\e[1;33m'
    BLUE=$'\e[1;34m' CYAN=$'\e[1;36m'   BOLD=$'\e[1m'
    DIM=$'\e[2m'     RESET=$'\e[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

log()         { printf '%s[*]%s %s\n'   "$BLUE"   "$RESET" "$1"; }
log_ok()      { printf '%s[✓]%s %s\n'   "$GREEN"  "$RESET" "$1"; }
log_warn()    { printf '%s[!]%s %s\n'   "$YELLOW" "$RESET" "$1"; }
log_error()   { printf '%s[✗]%s %s\n'   "$RED"    "$RESET" "$1" >&2; }
log_skip()    { printf '%s[-]%s %s\n'   "$DIM"    "$RESET" "$1"; }
log_section() { printf '\n%s%s── %s%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
divider()     { printf '%s%s%s\n' "$DIM" "─────────────────────────────────────────────" "$RESET"; }

# --- Guards ------------------------------------------------------------------
[[ $EUID -eq 0 ]] && { log_error "Do not run as root."; exit 1; }
[[ ! -f "$DEPS_FILE" ]] && { log_error "dependencies.conf not found: ${DEPS_FILE}"; exit 1; }
source "$DEPS_FILE"

# =============================================================================
# GLOBALS
# =============================================================================
AUR_HELPER=""

# Selections populated during interactive phase
SELECTED_TERMINAL=""
SELECTED_FILEMANAGER=""
SELECTED_BROWSER=""
SELECTED_EDITOR=""
SELECTED_MULTIPLEXER=""

CHOSEN_GPU_OFFICIAL=()
CHOSEN_GPU_AUR=()
CHOSEN_FM_EXTRAS=()

CHOSEN_BROWSER_OFFICIAL=()
CHOSEN_BROWSER_AUR=()
CHOSEN_EDITOR_OFFICIAL=()
CHOSEN_EDITOR_AUR=()
CHOSEN_MULTIPLEXER_OFFICIAL=()

declare -a OPT_OFFICIAL=()
declare -a OPT_AUR=()

FINAL_OFFICIAL=()
FINAL_AUR=()


# =============================================================================
# UI: present_choice
# Numbered menu, returns REPLY_PKG / REPLY_LABEL / REPLY_TYPE / REPLY_IDX
# =============================================================================
present_choice() {
    local title="$1" default_idx="$2"
    shift 2
    local -a entries=( "$@" )
    local count=${#entries[@]}

    printf '\n%s%s%s\n' "$BOLD" "$title" "$RESET"
    divider

    local i
    for (( i=0; i<count; i++ )); do
        local entry="${entries[$i]}"
        local pkg="${entry%%|*}"
        local rest="${entry#*|}"
        local label="${rest%%|*}"
        local num=$(( i+1 ))

        if (( num == default_idx )); then
            printf '  %s%d)%s %s  %s← default%s\n' "$CYAN" "$num" "$RESET" "$label" "$DIM" "$RESET"
        else
            printf '  %s%d)%s %s\n' "$CYAN" "$num" "$RESET" "$label"
        fi
    done
    printf '\n'

    local sel
    while true; do
        read -rp "  Selection [1-${count}, Enter=${default_idx}]: " sel
        sel="${sel:-${default_idx}}"
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= count )); then
            local chosen="${entries[$(( sel-1 ))]}"
            REPLY_PKG="${chosen%%|*}"
            local _rest="${chosen#*|}"
            REPLY_LABEL="${_rest%%|*}"
            REPLY_TYPE="${_rest##*|}"
            REPLY_IDX="$sel"
            return 0
        fi
        printf '  %sEnter a number 1–%d%s\n' "$RED" "$count" "$RESET"
    done
}


# =============================================================================
# UI: ask_optional
# Returns 0=yes  1=no
# =============================================================================
ask_optional() {
    local label="$1" desc="${2:-}" default="${3:-n}"
    printf '\n%s%s%s\n' "$BOLD" "$label" "$RESET"
    [[ -n "$desc" ]] && printf '  %s%s%s\n' "$DIM" "$desc" "$RESET"
    divider

    local prompt="  Install? [y/N]: "
    [[ "$default" == "y" ]] && prompt="  Install? [Y/n]: "
    local resp
    read -rp "$prompt" resp
    resp="${resp:-$default}"
    [[ "${resp,,}" =~ ^y ]]
}


# =============================================================================
# STEP 1 — AUR Helper
# =============================================================================
setup_aur_helper() {
    log_section "AUR Helper"

    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"; log_ok "Using paru"; return 0
    fi
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"; log_ok "Using yay"; return 0
    fi

    log_warn "No AUR helper found."
    printf '\n'
    printf '  %s1)%s Install paru  (Rust-based, recommended)\n' "$CYAN" "$RESET"
    printf '  %s2)%s Install yay   (Go-based, widely used)\n'   "$CYAN" "$RESET"
    printf '  %s3)%s Skip          (AUR packages will be omitted)\n' "$CYAN" "$RESET"
    printf '\n'

    local choice; read -rp "  Selection [1-3, Enter=1]: " choice; choice="${choice:-1}"

    local aur_pkg
    case "$choice" in
        2) aur_pkg="yay" ;; 3) log_warn "Skipping AUR helper."; return 0 ;; *) aur_pkg="paru" ;;
    esac

    log "Installing ${aur_pkg}..."
    sudo pacman -S --needed --noconfirm git base-devel

    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    git clone --depth 1 "https://aur.archlinux.org/${aur_pkg}.git" "${tmp}/${aur_pkg}"
    (cd "${tmp}/${aur_pkg}" && makepkg -si --noconfirm)

    if command -v "$aur_pkg" &>/dev/null; then
        AUR_HELPER="$aur_pkg"; log_ok "${aur_pkg} installed."
    else
        log_error "Failed to install ${aur_pkg}. AUR packages will be skipped."
    fi
}


# =============================================================================
# STEP 2 — GPU Detection
# =============================================================================
select_gpu() {
    log_section "GPU Drivers"

    local gpu; gpu="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | cut -d: -f3 | xargs 2>/dev/null)" || true
    local cpu; cpu="$(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | xargs 2>/dev/null)" || true
    printf '  CPU : %s\n' "${cpu:-Unknown}"
    printf '  GPU : %s\n' "${gpu:-Unknown}"
    printf '\n'

    local auto=""
    echo "$gpu" | grep -qi "nvidia"       && auto=1 && printf '  %s→ Detected NVIDIA%s\n' "$GREEN" "$RESET"
    echo "$gpu" | grep -qi "amd\|radeon"  && auto=2 && printf '  %s→ Detected AMD%s\n'   "$GREEN" "$RESET"
    echo "$gpu" | grep -qi "intel"        && auto=3 && printf '  %s→ Detected Intel%s\n' "$GREEN" "$RESET"

    printf '\n'
    printf '  %s1)%s NVIDIA  (nvidia-open-dkms — Turing/RTX 20xx+)\n'   "$CYAN" "$RESET"
    printf '  %s2)%s AMD     (mesa + vulkan-radeon)\n'                    "$CYAN" "$RESET"
    printf '  %s3)%s Intel   (mesa + vulkan-intel + intel-media-driver)\n' "$CYAN" "$RESET"
    printf '  %s4)%s Skip    (VM / already configured / dual GPU)\n'      "$CYAN" "$RESET"
    printf '\n'

    local default="${auto:-4}"; local choice
    read -rp "  Selection [1-4, Enter=${default}]: " choice
    choice="${choice:-${default}}"

    CHOSEN_GPU_OFFICIAL=(); CHOSEN_GPU_AUR=()
    case "$choice" in
        1)  CHOSEN_GPU_OFFICIAL=( "${OFFICIAL_GPU_NVIDIA[@]}" )
            CHOSEN_GPU_AUR=( "${AUR_GPU_NVIDIA[@]}" )
            log_ok "NVIDIA drivers selected."
            printf '\n  %sAdd to hyprland.conf env block:%s\n' "$YELLOW" "$RESET"
            printf '    env = LIBVA_DRIVER_NAME,nvidia\n'
            printf '    env = GBM_BACKEND,nvidia-drm\n'
            printf '    env = __GLX_VENDOR_LIBRARY_NAME,nvidia\n'
            printf '    env = NVD_BACKEND,direct\n' ;;
        2)  CHOSEN_GPU_OFFICIAL=( "${OFFICIAL_GPU_AMD[@]}" )
            log_ok "AMD drivers selected." ;;
        3)  CHOSEN_GPU_OFFICIAL=( "${OFFICIAL_GPU_INTEL[@]}" )
            log_ok "Intel drivers selected." ;;
        *)  log_skip "Skipping GPU drivers." ;;
    esac
}


# =============================================================================
# STEP 3 — Software Choices
# =============================================================================
make_choices() {
    log_section "Software Choices"
    printf '  Press Enter to accept the default for each.\n'

    # Terminal
    present_choice "Terminal Emulator" "$CHOICE_TERMINAL_DEFAULT" "${CHOICE_TERMINAL[@]}"
    SELECTED_TERMINAL="$REPLY_PKG"
    log_ok "Terminal: ${REPLY_LABEL}"

    # File Manager
    present_choice "File Manager" "$CHOICE_FILEMANAGER_DEFAULT" "${CHOICE_FILEMANAGER[@]}"
    SELECTED_FILEMANAGER="$REPLY_PKG"
    log_ok "File manager: ${REPLY_LABEL}"

    CHOSEN_FM_EXTRAS=()
    if [[ "$SELECTED_FILEMANAGER" != "none" ]]; then
        local extras_var="CHOICE_FILEMANAGER_EXTRAS_${SELECTED_FILEMANAGER}"
        if [[ -n "${!extras_var:-}" ]]; then
            read -ra CHOSEN_FM_EXTRAS <<< "${!extras_var}"
        fi
    fi

    # Browser
    present_choice "Browser" "$CHOICE_BROWSER_DEFAULT" "${CHOICE_BROWSER[@]}"
    CHOSEN_BROWSER_OFFICIAL=(); CHOSEN_BROWSER_AUR=()
    if [[ "$REPLY_PKG" != "none" ]]; then
        case "$REPLY_TYPE" in
            aur)      CHOSEN_BROWSER_AUR=( "$REPLY_PKG" ) ;;
            official) CHOSEN_BROWSER_OFFICIAL=( "$REPLY_PKG" ) ;;
        esac
    fi
    log_ok "Browser: ${REPLY_LABEL}"

    # Code Editor
    present_choice "Code Editor" "$CHOICE_EDITOR_DEFAULT" "${CHOICE_EDITOR[@]}"
    CHOSEN_EDITOR_OFFICIAL=(); CHOSEN_EDITOR_AUR=()
    if [[ "$REPLY_PKG" != "none" ]]; then
        case "$REPLY_TYPE" in
            aur)      CHOSEN_EDITOR_AUR=( "$REPLY_PKG" ) ;;
            official) CHOSEN_EDITOR_OFFICIAL=( "$REPLY_PKG" ) ;;
        esac
    fi
    log_ok "Editor: ${REPLY_LABEL}"

    # Multiplexer
    present_choice "Terminal Multiplexer" "$CHOICE_MULTIPLEXER_DEFAULT" "${CHOICE_MULTIPLEXER[@]}"
    CHOSEN_MULTIPLEXER_OFFICIAL=()
    [[ "$REPLY_TYPE" == "official" && "$REPLY_PKG" != "none" ]] && CHOSEN_MULTIPLEXER_OFFICIAL=( "$REPLY_PKG" )
    log_ok "Multiplexer: ${REPLY_LABEL}"
}


# =============================================================================
# STEP 4 — Optional Groups
# =============================================================================
select_optional() {
    log_section "Optional Software Groups"
    printf '  None of these are required for Hyprland to function.\n'
    printf '  Press Enter to skip, or type y to include.\n'

    OPT_OFFICIAL=(); OPT_AUR=()

    _add() {
        local -n _o="$1" _a="$2"
        OPT_OFFICIAL+=( "${_o[@]}" )
        OPT_AUR+=( "${_a[@]}" )
    }

    ask_optional "GUI Desktop Extras" \
        "Blueman, GNOME Calculator/Clocks/TextEditor, Loupe, Disk Utility, GParted, Seahorse, Errands, Collision, udiskie" \
        && _add OPTIONAL_OFFICIAL_GUI_EXTRAS OPTIONAL_AUR_GUI_EXTRAS

    ask_optional "CLI Power Tools" \
        "neovim, bat, eza, fzf, ripgrep, fd, yazi, tealdeer, imagemagick, chafa, gum, inxi, reflector, pacseek, dysk, wttr, caligula" \
        && _add OPTIONAL_OFFICIAL_CLI_TOOLS OPTIONAL_AUR_CLI_TOOLS

    ask_optional "TUI / Eye Candy" \
        "cava, pipes.sh, peaclock, bluetui, ttyper, keypunch, kew (music), tray-tui, wifitui" \
        && _add OPTIONAL_OFFICIAL_TUI_EYECANDY OPTIONAL_AUR_TUI_EYECANDY

    ask_optional "Media" \
        "mpv + mpris, HandBrake, OBS Studio, cameractrls, yt-dlp, swayimg, tesseract OCR" \
        && _add OPTIONAL_OFFICIAL_MEDIA OPTIONAL_AUR_MEDIA

    ask_optional "Development Tools" \
        "cmake, meson, mold, ccache, clang, shellcheck, shfmt, stylua, uv, linux-headers, github-cli, wev" \
        && _add OPTIONAL_OFFICIAL_DEV OPTIONAL_AUR_DEV

    ask_optional "Gaming" \
        "Steam, Gamemode, MangoHud, Lutris, ProtonUp-Qt, Heroic" \
        && _add OPTIONAL_OFFICIAL_GAMING OPTIONAL_AUR_GAMING

    ask_optional "Social & Connectivity" \
        "Vesktop (Discord + Vencord), KDEConnect (phone ↔ desktop)" \
        && _add OPTIONAL_OFFICIAL_SOCIAL OPTIONAL_AUR_SOCIAL

    ask_optional "Music" \
        "Spotify, Spicetify, termusic (TUI), kew (TUI music player)" \
        && _add OPTIONAL_OFFICIAL_MUSIC OPTIONAL_AUR_MUSIC

    ask_optional "Productivity" \
        "Obsidian, LibreOffice Still, Zathura PDF viewer, calcurse" \
        && _add OPTIONAL_OFFICIAL_PRODUCTIVITY OPTIONAL_AUR_PRODUCTIVITY

    ask_optional "Laptop / Power Management" \
        "TLP, thermald, powertop, fwupd, acpid, acpi_call (battery thresholds), intel-ucode — SKIP ON DESKTOP" \
        && _add OPTIONAL_OFFICIAL_LAPTOP OPTIONAL_AUR_LAPTOP

    ask_optional "Network & Connectivity Tools" \
        "firewalld, iwd, openconnect, aria2, qbittorrent, syncthing, localsend, ethtool, iftop, wavemon, filezilla" \
        && _add OPTIONAL_OFFICIAL_NETWORK OPTIONAL_AUR_NETWORK

    ask_optional "System Administration" \
        "btrfs-progs, ntfs-3g, lshw, usbutils, sysstat, arch-wiki, mesa-utils, vulkan-tools" \
        && _add OPTIONAL_OFFICIAL_SYSADMIN OPTIONAL_AUR_SYSADMIN

    ask_optional "Extra Fonts" \
        "Atkinson Hyperlegible Next (accessibility font)" \
        && _add OPTIONAL_OFFICIAL_FONTS OPTIONAL_AUR_FONTS
}


# =============================================================================
# BUILD FINAL PACKAGE LISTS
# =============================================================================
declare -gA _SEEN=()

_dedup() {
    local -n _target="$1"; shift
    local pkg
    for pkg in "$@"; do
        [[ -z "$pkg" ]] && continue
        if [[ -z "${_SEEN[$pkg]:-}" ]]; then
            _SEEN["$pkg"]=1; _target+=( "$pkg" )
        fi
    done
}

build_final_lists() {
    _SEEN=(); FINAL_OFFICIAL=(); FINAL_AUR=()

    _dedup FINAL_OFFICIAL \
        "${MANDATORY_OFFICIAL_COMPOSITOR[@]}" \
        "${MANDATORY_OFFICIAL_DAEMONS[@]}" \
        "${MANDATORY_OFFICIAL_AUDIO[@]}" \
        "${MANDATORY_OFFICIAL_INTERFACE[@]}" \
        "${MANDATORY_OFFICIAL_SCREENSHOT[@]}" \
        "${MANDATORY_OFFICIAL_SHELL[@]}" \
        "${MANDATORY_OFFICIAL_SYSTEM[@]}" \
        "${MANDATORY_OFFICIAL_THEMING[@]}" \
        "${MANDATORY_OFFICIAL_MONITORING[@]}" \
        "${CHOSEN_GPU_OFFICIAL[@]:-}" \
        "${CHOSEN_BROWSER_OFFICIAL[@]:-}" \
        "${CHOSEN_EDITOR_OFFICIAL[@]:-}" \
        "${CHOSEN_MULTIPLEXER_OFFICIAL[@]:-}" \
        "${OPT_OFFICIAL[@]:-}"

    # File manager + extras
    [[ -n "${SELECTED_TERMINAL:-}"    && "$SELECTED_TERMINAL"    != "none" ]] && _dedup FINAL_OFFICIAL "$SELECTED_TERMINAL"
    [[ -n "${SELECTED_FILEMANAGER:-}" && "$SELECTED_FILEMANAGER" != "none" ]] && _dedup FINAL_OFFICIAL "$SELECTED_FILEMANAGER"
    _dedup FINAL_OFFICIAL "${CHOSEN_FM_EXTRAS[@]:-}"

    _dedup FINAL_AUR \
        "${MANDATORY_AUR_DAEMONS[@]}" \
        "${MANDATORY_AUR_INTERFACE[@]}" \
        "${MANDATORY_AUR_THEMING[@]}" \
        "${CHOSEN_GPU_AUR[@]:-}" \
        "${CHOSEN_BROWSER_AUR[@]:-}" \
        "${CHOSEN_EDITOR_AUR[@]:-}" \
        "${OPT_AUR[@]:-}"
}


# =============================================================================
# SUMMARY & CONFIRM
# =============================================================================
show_summary() {
    build_final_lists

    local editor_name="none"
    [[ ${#CHOSEN_EDITOR_AUR[@]}      -gt 0 ]] && editor_name="${CHOSEN_EDITOR_AUR[0]}"
    [[ ${#CHOSEN_EDITOR_OFFICIAL[@]} -gt 0 ]] && editor_name="${CHOSEN_EDITOR_OFFICIAL[0]}"

    local browser_name="none"
    [[ ${#CHOSEN_BROWSER_AUR[@]}      -gt 0 ]] && browser_name="${CHOSEN_BROWSER_AUR[0]}"
    [[ ${#CHOSEN_BROWSER_OFFICIAL[@]} -gt 0 ]] && browser_name="${CHOSEN_BROWSER_OFFICIAL[0]}"

    printf '\n'
    printf '%s%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$BOLD" "$GREEN" "$RESET"
    printf '%s  cloudyy-linux — Install Summary%s\n'                    "$BOLD"         "$RESET"
    printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n'     "$GREEN"        "$RESET"
    printf '\n  %sYour choices%s\n'   "$BOLD" "$RESET"
    printf '    Terminal     : %s\n' "${SELECTED_TERMINAL:-none}"
    printf '    File Manager : %s\n' "${SELECTED_FILEMANAGER:-none}"
    printf '    Browser      : %s\n' "$browser_name"
    printf '    Editor       : %s\n' "$editor_name"
    printf '    Multiplexer  : %s\n' "${CHOSEN_MULTIPLEXER_OFFICIAL[*]:-none}"
    printf '\n  %sPackage counts%s\n' "$BOLD" "$RESET"
    printf '    Official (pacman)  : %d\n' "${#FINAL_OFFICIAL[@]}"
    printf '    AUR (%s)          : %d\n'  "${AUR_HELPER:-none}" "${#FINAL_AUR[@]}"
    printf '    Total              : %d\n' "$(( ${#FINAL_OFFICIAL[@]} + ${#FINAL_AUR[@]} ))"

    if [[ -z "$AUR_HELPER" ]] && (( ${#FINAL_AUR[@]} > 0 )); then
        printf '\n  %s⚠  No AUR helper — %d AUR packages will be skipped%s\n' \
            "$YELLOW" "${#FINAL_AUR[@]}" "$RESET"
    fi
    printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$GREEN" "$RESET"

    read -rp "  Begin installation? [Y/n]: " _c
    [[ "${_c,,}" == "n" ]] && { log "Cancelled."; exit 0; }
}


# =============================================================================
# INSTALLATION ENGINE
# =============================================================================
pacman_install() {
    local group="$1"; shift
    local -a pkgs=( "$@" ); [[ ${#pkgs[@]} -eq 0 ]] && return 0
    log "pacman [${group}] — ${#pkgs[@]} pkg(s)"
    if sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
        log_ok "${group}"; return 0
    fi
    log_warn "${group} — batch failed, retrying individually..."
    local fails=0
    for pkg in "${pkgs[@]}"; do
        if sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
            log_ok "  ✓ ${pkg}"
        else
            log_warn "  ✗ ${pkg}"; (( ++fails ))
        fi
    done
    (( fails > 0 )) && log_warn "${group}: ${fails} skipped."
    return 0
}

aur_install() {
    local group="$1"; shift
    local -a pkgs=( "$@" ); [[ ${#pkgs[@]} -eq 0 ]] && return 0
    if [[ -z "$AUR_HELPER" ]]; then
        log_warn "No AUR helper — skipping [${group}]"
        printf '  Skipped: %s\n' "${pkgs[*]}"
        return 0
    fi
    log "${AUR_HELPER} [${group}] — ${#pkgs[@]} pkg(s)"
    if "$AUR_HELPER" -S --needed --noconfirm "${pkgs[@]}"; then
        log_ok "${group}"; return 0
    fi
    log_warn "${group} — batch failed, retrying individually..."
    local fails=0
    for pkg in "${pkgs[@]}"; do
        if "$AUR_HELPER" -S --needed --noconfirm "$pkg" &>/dev/null; then
            log_ok "  ✓ ${pkg}"
        else
            log_warn "  ✗ ${pkg}"; (( ++fails ))
        fi
    done
    (( fails > 0 )) && log_warn "${group}: ${fails} skipped."
    return 0
}

configure_zram() {
    command -v zram-generator &>/dev/null || return 0
    local conf="/etc/systemd/zram-generator.conf"
    [[ -f "$conf" ]] && { log_skip "ZRAM already configured."; return 0; }
    log "Configuring ZRAM..."
    printf '[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n' \
        | sudo tee "$conf" >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl start "systemd-zram-setup@zram0.service" 2>/dev/null || true
    log_ok "ZRAM configured."
}

configure_bluetooth() {
    if pacman -Qi bluez &>/dev/null; then
        sudo systemctl enable --now bluetooth.service 2>/dev/null || true
        log_ok "Bluetooth service enabled."
    fi
}


# =============================================================================
# MAIN
# =============================================================================
main() {
    log_section "System Update"
    log "Running full system upgrade..."
    sudo pacman -Syu --noconfirm
    log_ok "System is up to date."

    setup_aur_helper
    select_gpu
    make_choices
    select_optional
    show_summary  # also calls build_final_lists

    log_section "Installing — Official Packages"
    pacman_install "Compositor"  "${MANDATORY_OFFICIAL_COMPOSITOR[@]}"
    pacman_install "Daemons"     "${MANDATORY_OFFICIAL_DAEMONS[@]}"
    pacman_install "Audio"       "${MANDATORY_OFFICIAL_AUDIO[@]}"
    pacman_install "Interface"   "${MANDATORY_OFFICIAL_INTERFACE[@]}"
    pacman_install "Screenshot"  "${MANDATORY_OFFICIAL_SCREENSHOT[@]}"
    pacman_install "Shell"       "${MANDATORY_OFFICIAL_SHELL[@]}"
    pacman_install "System"      "${MANDATORY_OFFICIAL_SYSTEM[@]}"
    pacman_install "Theming"     "${MANDATORY_OFFICIAL_THEMING[@]}"
    pacman_install "Monitoring"  "${MANDATORY_OFFICIAL_MONITORING[@]}"
    (( ${#CHOSEN_GPU_OFFICIAL[@]} > 0 )) && pacman_install "GPU Drivers" "${CHOSEN_GPU_OFFICIAL[@]}"

    # Choices
    local -a ch_official=()
    [[ -n "${SELECTED_TERMINAL:-}"    && "$SELECTED_TERMINAL"    != "none" ]] && ch_official+=( "$SELECTED_TERMINAL" )
    [[ -n "${SELECTED_FILEMANAGER:-}" && "$SELECTED_FILEMANAGER" != "none" ]] && ch_official+=( "$SELECTED_FILEMANAGER" )
    ch_official+=( "${CHOSEN_FM_EXTRAS[@]:-}" )
    ch_official+=( "${CHOSEN_BROWSER_OFFICIAL[@]:-}" )
    ch_official+=( "${CHOSEN_EDITOR_OFFICIAL[@]:-}" )
    ch_official+=( "${CHOSEN_MULTIPLEXER_OFFICIAL[@]:-}" )
    (( ${#ch_official[@]} > 0 )) && pacman_install "Your Choices" "${ch_official[@]}"

    (( ${#OPT_OFFICIAL[@]} > 0 )) && pacman_install "Optional Groups" "${OPT_OFFICIAL[@]}"

    log_section "Installing — AUR Packages"
    aur_install "Core AUR"    "${MANDATORY_AUR_DAEMONS[@]}"
    aur_install "Interface"   "${MANDATORY_AUR_INTERFACE[@]}"
    aur_install "Theming"     "${MANDATORY_AUR_THEMING[@]}"
    (( ${#CHOSEN_GPU_AUR[@]}    > 0 )) && aur_install "GPU AUR"    "${CHOSEN_GPU_AUR[@]}"
    (( ${#CHOSEN_BROWSER_AUR[@]} > 0 )) && aur_install "Browser"   "${CHOSEN_BROWSER_AUR[@]}"
    (( ${#CHOSEN_EDITOR_AUR[@]}  > 0 )) && aur_install "Editor"    "${CHOSEN_EDITOR_AUR[@]}"
    (( ${#OPT_AUR[@]}           > 0 )) && aur_install "Optional"  "${OPT_AUR[@]}"

    log_section "Post-Install"
    configure_zram
    configure_bluetooth

    printf '\n%s%s[✓] All done. Reboot recommended.%s\n\n' "$BOLD" "$GREEN" "$RESET"
}

main "$@"
